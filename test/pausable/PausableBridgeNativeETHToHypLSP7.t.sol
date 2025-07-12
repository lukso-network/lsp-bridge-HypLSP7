// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// test utilities
import { HypTokenTest } from "../helpers/HypTokenTest.sol";
import { formatHyperlaneMessage } from "../helpers/Utils.sol";
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

        // 4. Connect the collateral with the synthetic contract, and vice versa
        vm.prank(WARP_ROUTE_OWNER);
        HypTokenTest._enrollOriginTokenRouter(nativeCollateral, address(syntheticToken));

        vm.prank(WARP_ROUTE_OWNER);
        HypTokenTest._enrollDestinationTokenRouter(syntheticToken, address(nativeCollateral));

        // 5. setup the Pausable versions of the token routers + register freezer address on both chains
        originPausableTokenRouter = Freezable(address(nativeCollateral));
        destinationPausableTokenRouter = Freezable(address(syntheticToken));

        vm.prank(WARP_ROUTE_OWNER);
        Freezable(address(originPausableTokenRouter)).changeFreezer(FREEZER);
        vm.prank(WARP_ROUTE_OWNER);
        Freezable(address(destinationPausableTokenRouter)).changeFreezer(FREEZER);
    }

    // ==========================
    // |     Test Bridge Tx     |
    // |  Origin -> Destination |
    // ==========================

    function test_BridgeTxSuccessfulWhenNotPausedOnOriginOrDestination() public {
        _unpauseOrigin();
        _unpauseDestination();

        assertEq(syntheticToken.balanceOf(BOB), 0);

        uint256 _msgValue = REQUIRED_INTERCHAIN_GAS_PAYMENT + TRANSFER_AMOUNT;

        vm.prank(ALICE);
        nativeCollateral.transferRemote{ value: _msgValue }(
            DESTINATION_CHAIN_ID, BOB.addressToBytes32(), TRANSFER_AMOUNT
        );
        // TODO: assert for emitted event
        emit TokenRouter.ReceivedTransferRemote(ORIGIN_CHAIN_ID, BOB.addressToBytes32(), TRANSFER_AMOUNT);

        bytes memory _message = _prepareProcessCall(TRANSFER_AMOUNT);

        destinationMailbox.process("", _message); // we don't need metadata
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

        // bytes memory _message = _prepareProcessCall(_amount);
        bytes memory _tokenMessage = TokenMessage.format(BOB.addressToBytes32(), TRANSFER_AMOUNT, "");

        vm.expectRevert("Pausable: paused");
        destinationMailbox.testHandle(
            ORIGIN_CHAIN_ID,
            address(nativeCollateral).addressToBytes32(),
            address(syntheticToken).addressToBytes32(),
            _tokenMessage
        ); // we don't need metadata
    }

    // ==============================
    // |     Test Bridging Back     |
    // |    Origin <- Destination   |
    // ==============================

    function test_BridgeBackTxRevertsWhenPausedOnDestination() public {
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

    function test_BridgeBackTxRevertsWhenPausedOnOrigin() public {
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

    // Internal functions
    // --------------------

    /// @dev Prepare the call that the Hyperlane relayer should send on the destination chain
    /// to `Mailbox.process()`
    // TODO: create the version with `tokenId` as parameter
    function _prepareProcessCall(uint256 _amount) internal view returns (bytes memory) {
        // ============== WTF IS THIS ? ===========================
        // To test whether the warp route is paused we must call
        // Mailbox.process(_metadata, _message) on the destination side
        // calling remoteToken.handle() finalizes the cross chain transfer
        // and is only called if the ISM.verify() function returns true
        // so that method cannot be used here
        bytes memory tokenMessage = TokenMessage.format(BOB.addressToBytes32(), _amount, "");

        bytes32 originRouter = syntheticToken.routers(ORIGIN_CHAIN_ID);
        bytes32 encodedOriginTokenRouterAddress = address(nativeCollateral).addressToBytes32();
        bytes32 encodedDestinationTokenRouterAddress = address(syntheticToken).addressToBytes32();

        // Sanity CHECK to ensure the token router contract on the destination chain (= the synthetic token contract)
        // is connected to the correct token router contract on the origin chain (= the collateral contract)
        assertEq(originRouter, encodedOriginTokenRouterAddress);

        bytes memory message = formatHyperlaneMessage({
            _version: 3,
            _nonce: 1,
            // `HypNativePausable` token router on ORIGIN_CHAIN_ID
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
