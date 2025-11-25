// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// test utilities
import { HypTokenTest } from "../helpers/HypTokenTest.sol";
import { BridgeNativeETHToHypLSP7 } from "../native/BridgeNativeETHToHypLSP7.t.sol";
import { PausableControllerTester } from "../helpers/PausableControllerTester.sol";

/// Hyperlane testing environnement
/// @dev See https://docs.hyperlane.xyz/docs/guides/developer-tips/unit-testing
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";
import { TestIsm } from "@hyperlane-xyz/core/contracts/test/TestIsm.sol";
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";

// libraries
import { TokenMessage } from "@hyperlane-xyz/core/contracts/token/libs/TokenMessage.sol";
import { generateLSP4DataKeysAndValues } from "../helpers/Utils.sol";

// Modules to test
import { HypLSP7 } from "../../contracts/HypLSP7.sol";
import { HypLSP7Pausable } from "../../contracts/pausable/HypLSP7Pausable.sol";
import { HypNativePausable } from "../../contracts/pausable/HypNativePausable.sol";
import { PausableController } from "../../contracts/pausable/PausableController.sol";

/**
 * @title Bridge token routes tests from native tokens to `HypERC20`
 * + testing Pausable features on both ends of the chain
 *
 * @dev Hyperlane warp route tests.
 *  - origin chain: native tokens (LYX) locked in `HypNativePausable`
 *  - destination chain: synthetic tokens minted as `HypERC20Pausable`
 */
contract PausableBridgeNativeETHToHypLSP7 is BridgeNativeETHToHypLSP7, PausableControllerTester {
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
        HypTokenTest._connectOriginTokenRouter();

        vm.prank(WARP_ROUTE_OWNER);
        HypTokenTest._connectDestinationTokenRouter();

        // 6. setup the Pausable versions of the token routers
        // + register the address of the controller that can pause on both chains
        originPausableTokenRouter = PausableController(address(nativeCollateral));
        destinationPausableTokenRouter = PausableController(address(syntheticToken));

        vm.prank(WARP_ROUTE_OWNER);
        PausableController(address(originPausableTokenRouter)).changePausableController(PAUSABLE_CONTROLLER);
        vm.prank(WARP_ROUTE_OWNER);
        PausableController(address(destinationPausableTokenRouter)).changePausableController(PAUSABLE_CONTROLLER);
    }

    function test_deploymentConfigurationFlowSetMetadataPauserAndTransferOwnership() public {
        // Native collateral
        // -------------------------
        // Deployed + Initialized already done in setUp()

        // 3. setup the LSP4Metadata with `setDataBatch(...)` on destination chain
        (bytes32[] memory dataKeys, bytes[] memory dataValues) = generateLSP4DataKeysAndValues();
        assertEq(syntheticToken.getDataBatch(dataKeys), new bytes[](dataKeys.length)); // CHECK empty

        vm.prank(WARP_ROUTE_OWNER);
        syntheticToken.setDataBatch(dataKeys, dataValues);
        assertEq(syntheticToken.getDataBatch(dataKeys), dataValues); // CHECK values set

        // 4. setup the pauser address
        address newPauser = makeAddr("new pauser");
        assertEq(originPausableTokenRouter.pausableController(), PAUSABLE_CONTROLLER); // CHECK pauser not set
        assertEq(destinationPausableTokenRouter.pausableController(), PAUSABLE_CONTROLLER); // CHECK pauser not set

        vm.prank(WARP_ROUTE_OWNER);
        originPausableTokenRouter.changePausableController(newPauser);

        vm.prank(WARP_ROUTE_OWNER);
        destinationPausableTokenRouter.changePausableController(newPauser);

        assertEq(originPausableTokenRouter.pausableController(), newPauser); // CHECK pauser set
        assertEq(destinationPausableTokenRouter.pausableController(), newPauser);
        assertFalse(originPausableTokenRouter.disabledForever());
        assertFalse(destinationPausableTokenRouter.disabledForever());

        // 5. transfer ownership of the warp route to new owner
        assertEq(originPausableTokenRouter.owner(), WARP_ROUTE_OWNER); // CHECK owner is still the deployer
        assertEq(destinationPausableTokenRouter.owner(), WARP_ROUTE_OWNER); // CHECK owner

        address newOwner = makeAddr("newOwner");

        vm.prank(WARP_ROUTE_OWNER);
        originPausableTokenRouter.transferOwnership(newOwner);
        vm.prank(WARP_ROUTE_OWNER);
        destinationPausableTokenRouter.transferOwnership(newOwner);

        assertEq(originPausableTokenRouter.owner(), newOwner); // CHECK new owner set
        assertEq(destinationPausableTokenRouter.owner(), newOwner); // CHECK new owner set
    }

    function test_CanTransferSyntheticTokensBetweenAddressesOnDestinationChainEvenIfSyntheticTokenIsPaused(uint256 localTransferAmount)
        public
    {
        assertFalse(destinationPausableTokenRouter.paused());

        // Bridge tokens to BOB first on destination chain
        _performBridgeTxAndCheckSentTransferRemoteEvent({
            _msgValue: REQUIRED_INTERCHAIN_GAS_PAYMENT + TRANSFER_AMOUNT, _amount: TRANSFER_AMOUNT
        });

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

    function test_CanBridgeBackWhenNoPausableControllerRegistered() public {
        vm.prank(WARP_ROUTE_OWNER);
        PausableController(address(nativeCollateral))
            .changePausableController(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);

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
