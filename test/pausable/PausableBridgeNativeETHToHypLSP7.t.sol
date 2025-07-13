// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// test utilities
import { HypTokenTest } from "../helpers/HypTokenTest.sol";
import { BridgeNativeETHToHypLSP7 } from "../native/BridgeNativeETHToHypLSP7.t.sol";
import { FreezableTester } from "../helpers/FreezableTester.sol";

/// Hyperlane testing environnement
/// @dev See https://docs.hyperlane.xyz/docs/guides/developer-tips/unit-testing
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";
import { TestIsm } from "@hyperlane-xyz/core/contracts/test/TestIsm.sol";
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";

// libraries
import { TokenMessage } from "@hyperlane-xyz/core/contracts/token/libs/TokenMessage.sol";

// Modules to test
import { HypLSP7 } from "../../src/HypLSP7.sol";
import { HypLSP7Pausable } from "../../src/pausable/HypLSP7Pausable.sol";
import { HypNativePausable } from "../../src/pausable/HypNativePausable.sol";
import { Freezable } from "../../src/pausable/Freezable.sol";

/**
 * @title Bridge token routes tests from native tokens to `HypERC20`
 * + testing Pausable features on both ends of the chain
 *
 * @dev Hyperlane warp route tests.
 *  - origin chain: native tokens (LYX) locked in `HypNativePausable`
 *  - destination chain: synthetic tokens minted as `HypERC20Pausable`
 */
contract PausableBridgeNativeETHToHypLSP7 is BridgeNativeETHToHypLSP7, FreezableTester {
    using TypeCasts for address;

    function setUp() public override {
        ORIGIN_CHAIN_ID = 1; // Ethereum
        DESTINATION_CHAIN_ID = 42; // LUKSO

        REQUIRED_INTERCHAIN_GAS_PAYMENT = 10_000 gwei;

        HypTokenTest.setUp();

        /// 1. Give some native tokens to Alice to allow her to bridge
        vm.deal(ALICE, USER_BALANCE);

        // 2. Deploy Pausable version of collateral token router
        originDefaultHook = new TestPostDispatchHook();
        originDefaultIsm = new TestIsm();

        nativeCollateral = new HypNativePausable(SCALE_PARAM, address(originMailbox));
        nativeCollateral.initialize(address(originDefaultHook), address(originDefaultIsm), WARP_ROUTE_OWNER);

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
        originTokenRouter = nativeCollateral;
        destinationTokenRouter = syntheticToken;

        // 5. Connect the collateral with the synthetic contract, and vice versa
        vm.prank(WARP_ROUTE_OWNER);
        HypTokenTest._enrollOriginTokenRouter();

        vm.prank(WARP_ROUTE_OWNER);
        HypTokenTest._enrollDestinationTokenRouter();

        // 6. setup the Pausable versions of the token routers + register freezer address on both chains
        originPausableTokenRouter = Freezable(address(nativeCollateral));
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
        _performBridgeTxAndCheckSentTransferRemoteEvent({
            _msgValue: REQUIRED_INTERCHAIN_GAS_PAYMENT + TRANSFER_AMOUNT,
            _amount: TRANSFER_AMOUNT
        });

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

    function test_BridgeTxSuccessfulWhenNotPausedOnOriginOrDestination() public {
        _unpauseOrigin();
        _unpauseDestination();

        assertEq(syntheticToken.balanceOf(BOB), 0);

        uint256 msgValue = REQUIRED_INTERCHAIN_GAS_PAYMENT + TRANSFER_AMOUNT;

        vm.prank(ALICE);
        vm.expectEmit({ emitter: address(nativeCollateral) });
        emit TokenRouter.SentTransferRemote(DESTINATION_CHAIN_ID, BOB.addressToBytes32(), TRANSFER_AMOUNT);
        nativeCollateral.transferRemote{ value: msgValue }(
            DESTINATION_CHAIN_ID, BOB.addressToBytes32(), TRANSFER_AMOUNT
        );

        bytes memory message = HypTokenTest._prepareProcessCall(TRANSFER_AMOUNT);

        destinationMailbox.process("", message); // we don't need metadata
        assertEq(syntheticToken.balanceOf(BOB), TRANSFER_AMOUNT);
    }

    function test_BridgeTxRevertsOnOriginWhenPausedOnOrigin() public {
        _pauseOrigin();

        uint256 _msgValue = REQUIRED_INTERCHAIN_GAS_PAYMENT + TRANSFER_AMOUNT;

        vm.prank(ALICE);
        vm.expectRevert("Pausable: paused");
        nativeCollateral.transferRemote{ value: _msgValue }(
            DESTINATION_CHAIN_ID, BOB.addressToBytes32(), TRANSFER_AMOUNT
        );
    }

    function test_BridgeTxRevertsOnDestinationWhenPausedOnDestination() public {
        _pauseDestination();

        bytes memory tokenMessage = TokenMessage.format(BOB.addressToBytes32(), TRANSFER_AMOUNT, "");

        vm.expectRevert("Pausable: paused");
        destinationMailbox.testHandle(
            ORIGIN_CHAIN_ID,
            address(nativeCollateral).addressToBytes32(),
            address(syntheticToken).addressToBytes32(),
            tokenMessage
        ); // we don't need metadata
    }

    // ==============================
    // |     Test Bridging Back     |
    // |    Origin <- Destination   |
    // ==============================

    function test_BridgeBackTxRevertsOnDestinationWhenPausedOnDestination() public {
        // first make sure there is synthetic tokens available to ALICE
        bytes memory _message = TokenMessage.format(ALICE.addressToBytes32(), TRANSFER_AMOUNT, "");
        destinationMailbox.testHandle(
            ORIGIN_CHAIN_ID,
            address(nativeCollateral).addressToBytes32(),
            address(syntheticToken).addressToBytes32(),
            _message
        );

        _pauseDestination();
        vm.prank(ALICE);
        vm.expectRevert("Pausable: paused");
        syntheticToken.transferRemote(ORIGIN_CHAIN_ID, BOB.addressToBytes32(), TRANSFER_AMOUNT);
    }

    function test_BridgeBackTxRevertsOnOriginWhenPausedOnOrigin() public {
        _pauseOrigin();
        vm.prank(ALICE);

        bytes memory _tokenMessage = TokenMessage.format(BOB.addressToBytes32(), TRANSFER_AMOUNT, "");

        vm.expectRevert("Pausable: paused");
        originMailbox.testHandle(
            DESTINATION_CHAIN_ID,
            address(syntheticToken).addressToBytes32(),
            address(nativeCollateral).addressToBytes32(),
            _tokenMessage
        ); // we don't need metadata
    }

    function test_CanBridgeBackWhenNoFreezerRegistered() public {
        vm.prank(WARP_ROUTE_OWNER);
        Freezable(address(nativeCollateral)).changeFreezer(address(0));

        // assume some native tokens are locked in the native collateral contract
        // and need to be unlocked to be able to bridge back
        vm.deal(address(nativeCollateral), TRANSFER_AMOUNT);
        assertEq(address(nativeCollateral).balance, TRANSFER_AMOUNT);

        bytes memory _message = TokenMessage.format(BOB.addressToBytes32(), TRANSFER_AMOUNT, "");

        originMailbox.testHandle(
            DESTINATION_CHAIN_ID,
            address(syntheticToken).addressToBytes32(),
            address(nativeCollateral).addressToBytes32(),
            _message
        );
    }
}
