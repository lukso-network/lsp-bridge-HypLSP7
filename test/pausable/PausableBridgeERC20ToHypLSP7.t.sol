// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// test utilities
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import { HypTokenTest } from "../helpers/HypTokenTest.sol";
import { BridgeERC20ToHypLSP7 } from "../tokens/BridgeERC20ToHypLSP7.t.sol";
import { FreezableTester } from "../helpers/FreezableTester.sol";
import { formatHyperlaneMessage } from "../helpers/Utils.sol";

// libraries
import { TokenMessage } from "@hyperlane-xyz/core/contracts/token/libs/TokenMessage.sol";

// mocks
import { ERC20Mock } from "../helpers/ERC20Mock.sol";
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";
import { TestIsm } from "@hyperlane-xyz/core/contracts/test/TestIsm.sol";

// Contracts to test
import { HypERC20CollateralPausable } from "../../src/pausable/HypERC20CollateralPausable.sol";
import { HypLSP7Pausable } from "../../src/pausable/HypLSP7Pausable.sol";
import { HypLSP7 } from "../../src/HypLSP7.sol";
import { Freezable } from "../../src/pausable/Freezable.sol";

contract PausableBridgeERC20ToHypLSP7 is BridgeERC20ToHypLSP7, FreezableTester {
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

        // 4. Connect the collateral with the synthetic contract, and vice versa
        vm.prank(WARP_ROUTE_OWNER);
        HypTokenTest._enrollOriginTokenRouter(erc20Collateral, address(syntheticToken));

        vm.prank(WARP_ROUTE_OWNER);
        HypTokenTest._enrollDestinationTokenRouter(syntheticToken, address(erc20Collateral));

        // 5. setup the Pausable versions of the token routers + register freezer address on both chains
        originPausableTokenRouter = Freezable(address(erc20Collateral));
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
        token.approve(address(erc20Collateral), TRANSFER_AMOUNT);
        _performBridgeTxAndCheckSentTransferRemoteEvent(
            erc20Collateral, syntheticToken, REQUIRED_INTERCHAIN_GAS_PAYMENT, TRANSFER_AMOUNT
        );

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
        syntheticToken.transfer(BOB, recipient, localTransferAmount, true, "");

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
        token.approve(address(erc20Collateral), TRANSFER_AMOUNT);

        assertEq(originPausableTokenRouter.paused(), false);
        assertEq(destinationPausableTokenRouter.paused(), false);

        _pauseDestination();
        assertEq(destinationPausableTokenRouter.paused(), true);

        vm.prank(ALICE);
        erc20Collateral.transferRemote{ value: REQUIRED_INTERCHAIN_GAS_PAYMENT }(
            DESTINATION_CHAIN_ID, BOB.addressToBytes32(), TRANSFER_AMOUNT
        );
        assertEq(token.balanceOf(ALICE), balanceBefore - TRANSFER_AMOUNT);
        assertEq(token.balanceOf(address(erc20Collateral)), TRANSFER_AMOUNT);

        bytes memory message = _prepareProcessCall(TRANSFER_AMOUNT);

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
            address(erc20Collateral).addressToBytes32(),
            message
        );
    }

    // Internal functions
    // --------------------

    /// @dev Prepare the call that the Hyperlane relayer should send on the destination chain.
    /// The encoded bytes returned by this function can be used as parameter to call
    /// `Mailbox.process(_metadata, _message)` on the destination chain.
    ///
    /// This is useful for testing transactions that should revert on the destination chain by:
    ///     - if the `ISM.verify(...)` function will return `false`
    ///     - if a warp route is paused (will revert when `Mailbox.process(...)` on the destination chain call
    /// `remoteToken.handle(...)`)
    function _prepareProcessCall(uint256 amount) internal view returns (bytes memory) {
        bytes memory tokenMessage = TokenMessage.format(BOB.addressToBytes32(), amount, "");

        bytes32 originRouter = syntheticToken.routers(ORIGIN_CHAIN_ID);
        bytes32 encodedOriginTokenRouterAddress = address(erc20Collateral).addressToBytes32();
        bytes32 encodedDestinationTokenRouterAddress = address(syntheticToken).addressToBytes32();

        // Sanity CHECK to ensure the token router contract on the destination chain (= the synthetic token contract)
        // is connected to the correct token router contract on the origin chain (= the collateral contract)
        assertEq(originRouter, encodedOriginTokenRouterAddress);

        bytes memory message = formatHyperlaneMessage({
            _version: 3,
            _nonce: 1,
            // `HypLSP7CollateralPausable` token router on ORIGIN_CHAIN_ID
            _originDomain: ORIGIN_CHAIN_ID,
            _sender: encodedOriginTokenRouterAddress,
            // remote HypERC20Pausable token router on DESTINATION_CHAIN_ID
            _destinationDomain: DESTINATION_CHAIN_ID,
            _recipient: encodedDestinationTokenRouterAddress,
            // encoded instructions on 1) how much to send, 2) to which address
            _messageBody: tokenMessage
        });

        return message;
    }
}
