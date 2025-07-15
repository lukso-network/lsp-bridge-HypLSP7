// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// test utilities
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import { HypTokenTest } from "../helpers/HypTokenTest.sol";
import { BridgeLSP7ToHypERC20 } from "../tokens/BridgeLSP7ToHypERC20.t.sol";
import { FreezableTester } from "../helpers/FreezableTester.sol";

// libraries
import { TokenMessage } from "@hyperlane-xyz/core/contracts/token/libs/TokenMessage.sol";

// mocks
import { LSP7Mock } from "../helpers/LSP7Mock.sol";
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";
import { TestIsm } from "@hyperlane-xyz/core/contracts/test/TestIsm.sol";

// Contracts to test
import { HypLSP7CollateralPausable } from "../../src/pausable/HypLSP7CollateralPausable.sol";
import { HypERC20Pausable } from "../../src/pausable/HypERC20Pausable.sol";
import { HypERC20 } from "@hyperlane-xyz/core/contracts/token/HypERC20.sol";
import { Freezable } from "../../src/pausable/Freezable.sol";

contract PausableBridgeLSP7ToHypERC20 is BridgeLSP7ToHypERC20, FreezableTester {
    using TypeCasts for address;

    function setUp() public override {
        ORIGIN_CHAIN_ID = 1; // Ethereum
        DESTINATION_CHAIN_ID = 42; // LUKSO

        HypTokenTest.setUp();

        token = new LSP7Mock(NAME, SYMBOL, TOTAL_SUPPLY, address(this));
        token.transfer(address(this), ALICE, 100_000 * (10 ** DECIMALS), true, "");

        // 2. Deploy pausable version of collateral token router
        originDefaultHook = new TestPostDispatchHook();
        originDefaultIsm = new TestIsm();

        lsp7Collateral = new HypLSP7CollateralPausable(address(token), SCALE_PARAM, address(originMailbox));
        lsp7Collateral.initialize(address(originDefaultHook), address(originDefaultIsm), WARP_ROUTE_OWNER);

        // 3. Deploy the synthetic token on the destination chain + initialize it
        destinationDefaultHook = new TestPostDispatchHook();
        destinationDefaultIsm = new TestIsm();

        HypERC20Pausable implementation = new HypERC20Pausable(DECIMALS, SCALE_PARAM, address(destinationMailbox));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            PROXY_ADMIN,
            abi.encodeCall(
                HypERC20.initialize,
                (
                    0, // initial supply (do not mint any synthetic tokens on initialization)
                    NAME,
                    SYMBOL,
                    address(destinationDefaultHook),
                    address(destinationDefaultIsm),
                    WARP_ROUTE_OWNER
                )
            )
        );

        syntheticToken = HypERC20Pausable(payable(proxy));

        // 4. setup the state variable derives from `HypTokenTest` to ensure
        // the internal helper functions can be used
        originTokenRouter = lsp7Collateral;
        destinationTokenRouter = syntheticToken;

        // 5. Connect the collateral with the synthetic contract, and vice versa
        vm.prank(WARP_ROUTE_OWNER);
        HypTokenTest._enrollOriginTokenRouter();

        vm.prank(WARP_ROUTE_OWNER);
        HypTokenTest._enrollDestinationTokenRouter();

        // 6. setup the Pausable versions of the token routers + register freezer address on both chains
        originPausableTokenRouter = Freezable(address(lsp7Collateral));
        destinationPausableTokenRouter = Freezable(address(syntheticToken));

        vm.prank(WARP_ROUTE_OWNER);
        Freezable(address(originPausableTokenRouter)).changeFreezer(FREEZER);
        vm.prank(WARP_ROUTE_OWNER);
        Freezable(address(destinationPausableTokenRouter)).changeFreezer(FREEZER);
    }

    function test_CanTransferSyntheticTokensBetweenAddressesOnDestinationChainEvenIfSyntheticTokenIsPaused(
        uint256 localTransferAmount
    )
        public
    {
        assertEq(destinationPausableTokenRouter.paused(), false);

        // Bridge tokens to BOB first on destination chain
        vm.prank(ALICE);
        token.authorizeOperator(address(lsp7Collateral), TRANSFER_AMOUNT, "");
        _performBridgeTxAndCheckSentTransferRemoteEvent(REQUIRED_INTERCHAIN_GAS_PAYMENT, TRANSFER_AMOUNT);

        uint256 bobSyntheticTokenBalance = syntheticToken.balanceOf(BOB);
        assertEq(bobSyntheticTokenBalance, TRANSFER_AMOUNT);

        address recipient = makeAddr("recipient");
        assertEq(syntheticToken.balanceOf(recipient), 0);

        // Setup range of fuzzing parameter
        localTransferAmount = bound(localTransferAmount, 0, syntheticToken.balanceOf(BOB));

        _pauseDestination();
        assertEq(destinationPausableTokenRouter.paused(), true);

        // Perform local LSP7 token transfer on destination chain
        vm.prank(BOB);
        syntheticToken.transfer(recipient, localTransferAmount);

        assertEq(syntheticToken.balanceOf(BOB), bobSyntheticTokenBalance - localTransferAmount);
        assertEq(syntheticToken.balanceOf(recipient), localTransferAmount);

        // Sanity CHECK to ensure warp route is still paused (= bridging disabled)
        assertEq(destinationPausableTokenRouter.paused(), true);
    }

    // ==========================
    // |     Test Bridge Tx     |
    // |  Origin -> Destination |
    // ==========================

    function test_BridgeTxRevertsOnDestinationWhenPausedOnDestination() public {
        uint256 balanceBefore = token.balanceOf(ALICE);

        vm.prank(ALICE);
        token.authorizeOperator(address(lsp7Collateral), TRANSFER_AMOUNT, "");

        assertEq(originPausableTokenRouter.paused(), false);
        assertEq(destinationPausableTokenRouter.paused(), false);

        _pauseDestination();
        assertEq(destinationPausableTokenRouter.paused(), true);

        vm.prank(ALICE);
        lsp7Collateral.transferRemote{ value: REQUIRED_INTERCHAIN_GAS_PAYMENT }(
            DESTINATION_CHAIN_ID, BOB.addressToBytes32(), TRANSFER_AMOUNT
        );
        assertEq(token.balanceOf(ALICE), balanceBefore - TRANSFER_AMOUNT);
        assertEq(token.balanceOf(address(lsp7Collateral)), TRANSFER_AMOUNT);

        bytes memory message = HypTokenTest._prepareProcessCall(TRANSFER_AMOUNT);

        vm.expectRevert("Pausable: paused");
        destinationMailbox.process("", message); // we don't need metadata
    }

    // ==============================
    // |     Test Bridging Back     |
    // |    Origin <- Destination   |
    // ==============================

    function test_BridgeBackTxRevertsOnDestinationWhenPausedOnDestination() public {
        assertEq(originPausableTokenRouter.paused(), false);
        assertEq(destinationPausableTokenRouter.paused(), false);

        _pauseDestination();
        assertEq(destinationPausableTokenRouter.paused(), true);

        vm.expectRevert("Pausable: paused");
        vm.prank(ALICE);
        syntheticToken.transferRemote{ value: REQUIRED_INTERCHAIN_GAS_PAYMENT }(
            ORIGIN_CHAIN_ID, BOB.addressToBytes32(), TRANSFER_AMOUNT
        );
    }

    function test_BridgeBackTxRevertsOnOriginWhenPausedOnOrigin() public {
        assertEq(originPausableTokenRouter.paused(), false);
        assertEq(destinationPausableTokenRouter.paused(), false);

        _pauseOrigin();
        assertEq(originPausableTokenRouter.paused(), true);

        bytes memory message = TokenMessage.format(BOB.addressToBytes32(), TRANSFER_AMOUNT, "");
        vm.expectRevert("Pausable: paused");
        originMailbox.testHandle(
            DESTINATION_CHAIN_ID,
            address(syntheticToken).addressToBytes32(),
            address(lsp7Collateral).addressToBytes32(),
            message
        );
    }
}
