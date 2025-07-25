// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// test utilities
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import { HypTokenTest } from "../helpers/HypTokenTest.sol";
import { BridgeERC20ToHypLSP7 } from "../tokens/BridgeERC20ToHypLSP7.t.sol";
import { PausableControllerTester } from "../helpers/PausableControllerTester.sol";

// libraries
import { TokenMessage } from "@hyperlane-xyz/core/contracts/token/libs/TokenMessage.sol";

// mocks
import { ERC20Mock } from "../helpers/ERC20Mock.sol";
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";
import { TestIsm } from "@hyperlane-xyz/core/contracts/test/TestIsm.sol";

// Contracts to test
import { HypERC20CollateralPausable } from "../../contracts/pausable/HypERC20CollateralPausable.sol";
import { HypLSP7Pausable } from "../../contracts/pausable/HypLSP7Pausable.sol";
import { HypLSP7 } from "../../contracts/HypLSP7.sol";
import { PausableController } from "../../contracts/pausable/PausableController.sol";

contract PausableBridgeERC20ToHypLSP7 is BridgeERC20ToHypLSP7, PausableControllerTester {
    using TypeCasts for address;

    function setUp() public override {
        ORIGIN_CHAIN_ID = 1; // Ethereum
        DESTINATION_CHAIN_ID = 42; // LUKSO

        HypTokenTest.setUp();

        token = new ERC20Mock(NAME, SYMBOL, TOTAL_SUPPLY, DECIMALS);
        token.transfer(ALICE, 100_000 * (10 ** DECIMALS));

        // 2. Deploy pausable version of collateral token router
        originDefaultHook = new TestPostDispatchHook();
        originDefaultIsm = new TestIsm();

        erc20Collateral = new HypERC20CollateralPausable(address(token), SCALE_PARAM, address(originMailbox));
        erc20Collateral.initialize(address(originDefaultHook), address(originDefaultIsm), WARP_ROUTE_OWNER);

        // 3. Deploy the synthetic token on the destination chain + initialize it
        destinationDefaultHook = new TestPostDispatchHook();
        destinationDefaultIsm = new TestIsm();

        HypLSP7Pausable implementation = new HypLSP7Pausable(DECIMALS, SCALE_PARAM, address(destinationMailbox));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            PROXY_ADMIN,
            abi.encodeCall(
                HypLSP7.initialize,
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

        syntheticToken = HypLSP7Pausable(payable(proxy));

        // 4. setup the state variable derives from `HypTokenTest` to ensure
        // the internal helper functions can be used
        originTokenRouter = erc20Collateral;
        destinationTokenRouter = syntheticToken;

        // 5. Connect the collateral with the synthetic contract, and vice versa
        vm.prank(WARP_ROUTE_OWNER);
        HypTokenTest._enrollOriginTokenRouter();

        vm.prank(WARP_ROUTE_OWNER);
        HypTokenTest._enrollDestinationTokenRouter();

        // 6. setup the Pausable versions of the token routers
        // + register the address of the controller that can pause on both chains
        originPausableTokenRouter = PausableController(address(erc20Collateral));
        destinationPausableTokenRouter = PausableController(address(syntheticToken));

        vm.prank(WARP_ROUTE_OWNER);
        PausableController(address(originPausableTokenRouter)).changePausableController(PAUSABLE_CONTROLLER);
        vm.prank(WARP_ROUTE_OWNER);
        PausableController(address(destinationPausableTokenRouter)).changePausableController(PAUSABLE_CONTROLLER);
    }

    function test_CanTransferSyntheticTokensBetweenAddressesOnDestinationChainEvenIfSyntheticTokenIsPaused(
        uint256 localTransferAmount
    )
        public
    {
        assertFalse(destinationPausableTokenRouter.paused());

        // Bridge tokens to BOB first on destination chain
        vm.prank(ALICE);
        token.approve(address(erc20Collateral), TRANSFER_AMOUNT);
        _performBridgeTxAndCheckSentTransferRemoteEvent(REQUIRED_INTERCHAIN_GAS_PAYMENT, TRANSFER_AMOUNT);

        uint256 bobSyntheticTokenBalance = syntheticToken.balanceOf(BOB);
        assertEq(bobSyntheticTokenBalance, TRANSFER_AMOUNT);

        address recipient = makeAddr("recipient");
        assertEq(syntheticToken.balanceOf(recipient), 0);

        // Setup range of fuzzing parameter
        localTransferAmount = bound(localTransferAmount, 0, syntheticToken.balanceOf(BOB));

        _pauseDestination();
        assertTrue(destinationPausableTokenRouter.paused());

        // Perform local LSP7 token transfer on destination chain
        vm.prank(BOB);
        syntheticToken.transfer(BOB, recipient, localTransferAmount, true, "");

        assertEq(syntheticToken.balanceOf(BOB), bobSyntheticTokenBalance - localTransferAmount);
        assertEq(syntheticToken.balanceOf(recipient), localTransferAmount);

        // Sanity CHECK to ensure warp route is still paused (= bridging disabled)
        assertTrue(destinationPausableTokenRouter.paused());
    }

    // ==========================
    // |     Test Bridge Tx     |
    // |  Origin -> Destination |
    // ==========================

    function test_BridgeTxRevertsOnDestinationWhenPausedOnDestination() public {
        uint256 balanceBefore = token.balanceOf(ALICE);

        vm.prank(ALICE);
        token.approve(address(erc20Collateral), TRANSFER_AMOUNT);

        assertFalse(originPausableTokenRouter.paused());
        assertFalse(destinationPausableTokenRouter.paused());

        _pauseDestination();
        assertTrue(destinationPausableTokenRouter.paused());

        vm.prank(ALICE);
        erc20Collateral.transferRemote{ value: REQUIRED_INTERCHAIN_GAS_PAYMENT }(
            DESTINATION_CHAIN_ID, BOB.addressToBytes32(), TRANSFER_AMOUNT
        );
        assertEq(token.balanceOf(ALICE), balanceBefore - TRANSFER_AMOUNT);
        assertEq(token.balanceOf(address(erc20Collateral)), TRANSFER_AMOUNT);

        bytes memory message = HypTokenTest._prepareProcessCall(TRANSFER_AMOUNT);

        vm.expectRevert("Pausable: paused");
        destinationMailbox.process("", message); // we don't need metadata
    }

    // ==============================
    // |     Test Bridging Back     |
    // |    Origin <- Destination   |
    // ==============================

    function test_BridgeBackTxRevertsOnDestinationWhenPausedOnDestination() public {
        assertFalse(originPausableTokenRouter.paused());
        assertFalse(destinationPausableTokenRouter.paused());

        _pauseDestination();
        assertTrue(destinationPausableTokenRouter.paused());

        vm.expectRevert("Pausable: paused");
        vm.prank(ALICE);
        syntheticToken.transferRemote{ value: REQUIRED_INTERCHAIN_GAS_PAYMENT }(
            ORIGIN_CHAIN_ID, BOB.addressToBytes32(), TRANSFER_AMOUNT
        );
    }

    function test_BridgeBackTxRevertsOnOriginWhenPausedOnOrigin() public {
        assertFalse(originPausableTokenRouter.paused());
        assertFalse(destinationPausableTokenRouter.paused());

        _pauseOrigin();
        assertTrue(originPausableTokenRouter.paused());

        bytes memory message = TokenMessage.format(BOB.addressToBytes32(), TRANSFER_AMOUNT, "");
        vm.expectRevert("Pausable: paused");
        originMailbox.testHandle(
            DESTINATION_CHAIN_ID,
            address(syntheticToken).addressToBytes32(),
            address(erc20Collateral).addressToBytes32(),
            message
        );
    }

    function test_CanBridgeBackWhenNoPausableControllerRegistered() public {
        vm.prank(WARP_ROUTE_OWNER);
        PausableController(address(erc20Collateral)).changePausableController(
            0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF
        );

        // assume some erc20 tokens are locked in the collateral contract
        // and need to be unlocked to be able to bridge back
        token.transfer(address(erc20Collateral), TRANSFER_AMOUNT);
        assertEq(token.balanceOf(address(erc20Collateral)), TRANSFER_AMOUNT);

        bytes memory _message = TokenMessage.format(BOB.addressToBytes32(), TRANSFER_AMOUNT, "");

        originMailbox.testHandle(
            DESTINATION_CHAIN_ID,
            address(syntheticToken).addressToBytes32(),
            address(erc20Collateral).addressToBytes32(),
            _message
        );
    }
}
