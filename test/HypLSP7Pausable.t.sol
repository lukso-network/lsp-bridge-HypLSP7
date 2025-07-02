// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// test utilities
import { Vm } from "forge-std/src/Vm.sol";
import { HypTokenTest } from "./helpers/HypTokenTest.sol";
import { SAMPLE_METADATA_BYTES } from "./helpers/Utils.sol";

/// Hyperlane testing environnement
/// @dev See https://docs.hyperlane.xyz/docs/guides/developer-tips/unit-testing

// - Mock test contracts
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";
import { TestIsm } from "@hyperlane-xyz/core/contracts/test/TestIsm.sol";

// - Hyperlane types and modules
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";

// - Hyperlane libraries
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";
import { TokenMessage } from "@hyperlane-xyz/core/contracts/token/libs/TokenMessage.sol";

// Mocks + contracts to test
import { LSP7Mock } from "./helpers/LSP7Mock.sol";
import { HypLSP7Pausable } from "../src/pausable/HypLSP7Pausable.sol";
import { HypLSP7CollateralPausable } from "../src/pausable/HypLSP7CollateralPausable.sol";
import { Freezable } from "../src/pausable/Freezable.sol";
import { IERC725Y } from "@erc725/smart-contracts/contracts/interfaces/IERC725Y.sol";

// constants
import { _INTERFACEID_LSP0 } from "@lukso/lsp0-contracts/contracts/LSP0Constants.sol";
import {
    _LSP4_TOKEN_TYPE_TOKEN,
    _LSP4_SUPPORTED_STANDARDS_KEY,
    _LSP4_TOKEN_NAME_KEY,
    _LSP4_TOKEN_SYMBOL_KEY,
    _LSP4_TOKEN_TYPE_KEY,
    _LSP4_CREATORS_ARRAY_KEY,
    _LSP4_CREATORS_MAP_KEY_PREFIX,
    _LSP4_METADATA_KEY
} from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";

abstract contract HypTokenPausableTest is HypTokenTest {
    using TypeCasts for address;

    address internal FREEZER = makeAddr("freezer");

    Freezable pausableLocalToken;
    Freezable pausableRemoteToken;

    function setUp() public virtual override {
        super.setUp();

        pausableLocalToken = Freezable(address(localToken));
        pausableRemoteToken = Freezable(address(remoteToken));

        vm.prank(WARP_ROUTE_OWNER);
        pausableRemoteToken.changeFreezer(FREEZER);
    }

    function _pauseLocal() internal {
        if (!pausableLocalToken.paused()) {
            vm.prank(FREEZER);
            pausableLocalToken.pause();
        }
        assertEq(pausableLocalToken.paused(), true);
    }

    function _unpauseLocal() internal {
        if (pausableLocalToken.paused()) {
            vm.prank(WARP_ROUTE_OWNER);
            pausableLocalToken.unpause();
        }
        assertEq(pausableLocalToken.paused(), false);
    }

    function _pauseRemote() internal {
        if (!pausableRemoteToken.paused()) {
            vm.prank(FREEZER);
            pausableRemoteToken.pause();
        }
        assertEq(pausableRemoteToken.paused(), true);
    }

    function _unpauseRemote() internal {
        if (pausableRemoteToken.paused()) {
            vm.prank(WARP_ROUTE_OWNER);
            pausableRemoteToken.unpause();
        }
        assertEq(pausableRemoteToken.paused(), false);
    }

    function _performRemoteTransferPauseRevert(uint256 _msgValue, uint256 _amount) internal {
        _pauseRemote();
        vm.prank(ALICE);
        localToken.transferRemote{ value: _msgValue }(DESTINATION, BOB.addressToBytes32(), _amount);
        emit TokenRouter.ReceivedTransferRemote(ORIGIN, BOB.addressToBytes32(), _amount);

        bytes memory _message = _prepareProcessCall(_amount);

        vm.expectRevert("Pausable: paused");
        remoteMailbox.process("", _message); // we don't need metadata
    }

    function _performRemoteTransferNoPause(uint256 _msgValue, uint256 _amount) internal {
        _unpauseRemote();

        assertEq(remoteToken.balanceOf(BOB), 0);

        vm.prank(ALICE);
        localToken.transferRemote{ value: _msgValue }(DESTINATION, BOB.addressToBytes32(), _amount);

        emit TokenRouter.ReceivedTransferRemote(ORIGIN, BOB.addressToBytes32(), _amount);

        bytes memory _message = _prepareProcessCall(_amount);

        remoteMailbox.process("", _message); // we don't need metadata
        assertEq(remoteToken.balanceOf(BOB), _amount);
    }

    function _performTransferToSyntheticLocalPaused(uint256 _msgValue, uint256 _amount) internal {
        _pauseLocal();

        assertEq(remoteToken.balanceOf(BOB), 0);
        uint256 aliceBalance = localToken.balanceOf(ALICE);

        vm.expectRevert("Pausable: paused");
        vm.prank(ALICE);
        localToken.transferRemote{ value: _msgValue }(DESTINATION, BOB.addressToBytes32(), _amount);

        assertEq(aliceBalance, localToken.balanceOf(ALICE));
    }

    function _performTransferToSyntheticRemotePaused(uint256 _msgValue, uint256 _amount) internal {
        _pauseRemote();

        bytes memory _message = TokenMessage.format(BOB.addressToBytes32(), _amount, "");
        vm.expectRevert("Pausable: paused");
        vm.prank(ALICE);
        remoteMailbox.testHandle(
            ORIGIN, address(localToken).addressToBytes32(), address(remoteToken).addressToBytes32(), _message
        );
    }

    function _performTransferToCollateralRemotePaused(uint256 _msgValue, uint256 _amount) internal {
        _pauseRemote();

        assertEq(remoteToken.balanceOf(BOB), 0);
        uint256 aliceBalance = localToken.balanceOf(ALICE);

        vm.expectRevert("Pausable: paused");
        vm.prank(ALICE);
        remoteToken.transferRemote{ value: _msgValue }(DESTINATION, BOB.addressToBytes32(), _amount);

        assertEq(aliceBalance, localToken.balanceOf(ALICE));
    }

    function _performTransferToCollateralLocalPaused(uint256 _msgValue, uint256 _amount) internal {
        _pauseLocal();

        bytes memory _message = TokenMessage.format(BOB.addressToBytes32(), _amount, "");
        vm.expectRevert("Pausable: paused");
        localMailbox.testHandle(
            DESTINATION, address(remoteToken).addressToBytes32(), address(localToken).addressToBytes32(), _message
        );
    }
}

contract HypLSP7PausableTest is HypTokenPausableTest {
    using TypeCasts for address;

    HypLSP7Pausable internal hypLSP7Token;
    TestIsm internal testIsm;

    function setUp() public override {
        super.setUp();

        testIsm = new TestIsm();

        localToken = new HypLSP7Pausable(DECIMALS, SCALE_SYNTHETIC, address(localMailbox));
        hypLSP7Token = HypLSP7Pausable(payable(address(localToken)));

        vm.prank(WARP_ROUTE_OWNER);
        hypLSP7Token.initialize(TOTAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(testIsm), WARP_ROUTE_OWNER);

        vm.prank(WARP_ROUTE_OWNER);
        hypLSP7Token.enrollRemoteRouter(DESTINATION, address(remoteToken).addressToBytes32());

        // from, to, amount, force, data
        vm.startPrank(WARP_ROUTE_OWNER);
        hypLSP7Token.transfer(WARP_ROUTE_OWNER, ALICE, 1000e18, true, "");
        hypLSP7Token.changeFreezer(FREEZER);
        vm.stopPrank();

        _enrollRemoteTokenRouter();
    }

    function testInitialize_revert_ifAlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        hypLSP7Token.initialize(TOTAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), WARP_ROUTE_OWNER);
    }

    function testLSP4MetadataIsSet() public {
        vm.skip(true);
        assertEq(hypLSP7Token.getData(_LSP4_METADATA_KEY), SAMPLE_METADATA_BYTES);
    }

    function testEmitDataChangedEventWhenMetadataBytesProvided() public {
        vm.skip(true);
        vm.prank(WARP_ROUTE_OWNER);
        HypLSP7Pausable someHypLSP7Token = new HypLSP7Pausable(DECIMALS, SCALE_SYNTHETIC, address(localMailbox));

        vm.expectEmit({ checkTopic1: true, checkTopic2: false, checkTopic3: false, checkData: true });
        emit IERC725Y.DataChanged(_LSP4_METADATA_KEY, SAMPLE_METADATA_BYTES);

        // (bytes32[] memory dataKeys, bytes[] memory dataValues) = _getInitDataKeysAndValues();

        someHypLSP7Token.initialize(TOTAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), WARP_ROUTE_OWNER);
    }

    function testNoDataChangedEventEmittedIfNoMetadataBytesProvided() public {
        vm.skip(true);
        // Capture logs before the transaction
        vm.recordLogs();

        HypLSP7Pausable someHypLSP7Token = new HypLSP7Pausable(DECIMALS, SCALE_SYNTHETIC, address(localMailbox));

        // (bytes32[] memory dataKeys, bytes[] memory dataValues) = (new bytes32[](0), new bytes[](0));

        // initialize token without metadata bytes
        vm.prank(WARP_ROUTE_OWNER);
        someHypLSP7Token.initialize(TOTAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), WARP_ROUTE_OWNER);

        // Search all the logs
        Vm.Log[] memory emittedEvents = vm.getRecordedLogs();
        for (uint256 i = 0; i < emittedEvents.length; i++) {
            // Check that no `DataChanged` event was emitted for the `LSP4Metadata` data key
            bool hasUpdatedLSP4MetadataKey = bytes32(emittedEvents[i].topics[0]) == IERC725Y.DataChanged.selector
                && emittedEvents[i].topics[1] == _LSP4_METADATA_KEY;

            assertFalse(
                hasUpdatedLSP4MetadataKey,
                "DataChanged event should not have been emitted because no metadata bytes were provided"
            );
        }
    }

    function testTotalSupply() public view {
        assertEq(hypLSP7Token.totalSupply(), TOTAL_SUPPLY);
    }

    function testDecimals() public view {
        assertEq(hypLSP7Token.decimals(), DECIMALS);
    }

    function testLocalTransfers() public {
        assertEq(hypLSP7Token.balanceOf(ALICE), 1000e18);
        assertEq(hypLSP7Token.balanceOf(BOB), 0);

        vm.prank(ALICE);
        hypLSP7Token.transfer(ALICE, BOB, 100e18, true, "");
        assertEq(hypLSP7Token.balanceOf(ALICE), 900e18);
        assertEq(hypLSP7Token.balanceOf(BOB), 100e18);
    }

    function testRemoteTransfer() public {
        vm.prank(WARP_ROUTE_OWNER);
        remoteToken.enrollRemoteRouter(ORIGIN, address(localToken).addressToBytes32());
        uint256 balanceBefore = hypLSP7Token.balanceOf(ALICE);

        _performRemoteTransferWithEmit(REQUIRED_INTERCHAIN_GAS_PAYMENT, TRANSFER_AMOUNT, 0);
        assertEq(hypLSP7Token.balanceOf(ALICE), balanceBefore - TRANSFER_AMOUNT);
    }

    function testRemoteTransfer_invalidAmount() public {
        vm.expectRevert();
        _performRemoteTransfer(REQUIRED_INTERCHAIN_GAS_PAYMENT, TRANSFER_AMOUNT * 11);
        assertEq(hypLSP7Token.balanceOf(ALICE), 1000e18);
    }

    function testRemoteTransfer_withCustomGasConfig() public {
        _setCustomGasConfig();

        uint256 balanceBefore = hypLSP7Token.balanceOf(ALICE);

        _performRemoteTransferAndGas(
            REQUIRED_INTERCHAIN_GAS_PAYMENT, TRANSFER_AMOUNT, GAS_LIMIT * interchainGasPaymaster.gasPrice()
        );

        assertEq(hypLSP7Token.balanceOf(ALICE), balanceBefore - TRANSFER_AMOUNT);
    }
    /**
     * Deprecated
     */
    // function testRemoteTransfer_paused() public {
    //     _performRemoteTransferPauseRevert(REQUIRED_INTERCHAIN_GAS_PAYMENT, TRANSFER_AMOUNT);
    // }

    function testRemoteTransfer_unpaused() public {
        _performRemoteTransferNoPause(REQUIRED_INTERCHAIN_GAS_PAYMENT, TRANSFER_AMOUNT);
    }

    function testRemoteTransferToSyntheticLocalPaused() public {
        _performTransferToSyntheticLocalPaused(REQUIRED_INTERCHAIN_GAS_PAYMENT, TRANSFER_AMOUNT);
    }

    function testTransferToSyntheticRemotePaused() public {
        _performTransferToSyntheticRemotePaused(REQUIRED_INTERCHAIN_GAS_PAYMENT, TRANSFER_AMOUNT);
    }
}

contract HypLSP7CollateralPausableTest is HypTokenPausableTest {
    using TypeCasts for address;

    HypLSP7CollateralPausable internal lsp7Collateral;
    TestIsm internal testIsm;

    function setUp() public override {
        super.setUp();

        testIsm = new TestIsm();

        localToken = new HypLSP7CollateralPausable(address(primaryToken), SCALE_SYNTHETIC, address(localMailbox));

        lsp7Collateral = HypLSP7CollateralPausable(address(localToken));

        lsp7Collateral.initialize(address(noopHook), address(testIsm), WARP_ROUTE_OWNER);

        vm.startPrank(WARP_ROUTE_OWNER);
        lsp7Collateral.enrollRemoteRouter(DESTINATION, address(remoteToken).addressToBytes32());
        lsp7Collateral.changeFreezer(FREEZER);
        vm.stopPrank();

        primaryToken.transfer(address(this), address(localToken), 1000e18, true, "");

        primaryToken.transfer(address(this), ALICE, 1000e18, true, "");

        _enrollRemoteTokenRouter();
    }

    function test_constructor_revert_ifInvalidToken() public {
        vm.expectRevert("HypLSP7Collateral: invalid token");
        new HypLSP7CollateralPausable(address(0), SCALE_SYNTHETIC, address(localMailbox));
    }

    function testRemoteTransfer() public {
        uint256 balanceBefore = localToken.balanceOf(ALICE);

        vm.prank(ALICE);
        primaryToken.authorizeOperator(address(localToken), TRANSFER_AMOUNT, "");

        _performRemoteTransferWithEmit(REQUIRED_INTERCHAIN_GAS_PAYMENT, TRANSFER_AMOUNT, 0);
        assertEq(localToken.balanceOf(ALICE), balanceBefore - TRANSFER_AMOUNT);
    }

    function testRemoteTransfer_invalidAllowance() public {
        vm.expectRevert();
        _performRemoteTransfer(REQUIRED_INTERCHAIN_GAS_PAYMENT, TRANSFER_AMOUNT);
        assertEq(localToken.balanceOf(ALICE), 1000e18);
    }

    function testRemoteTransfer_withCustomGasConfig() public {
        _setCustomGasConfig();

        uint256 balanceBefore = localToken.balanceOf(ALICE);

        vm.prank(ALICE);
        primaryToken.authorizeOperator(address(localToken), TRANSFER_AMOUNT, "");
        _performRemoteTransferAndGas(
            REQUIRED_INTERCHAIN_GAS_PAYMENT, TRANSFER_AMOUNT, GAS_LIMIT * interchainGasPaymaster.gasPrice()
        );
        assertEq(localToken.balanceOf(ALICE), balanceBefore - TRANSFER_AMOUNT);
    }

    function testTransferToCollateral_paused() public {
        uint256 balanceBefore = localToken.balanceOf(ALICE);

        vm.prank(ALICE);
        primaryToken.authorizeOperator(address(localToken), TRANSFER_AMOUNT, "");
        _performRemoteTransferPauseRevert(REQUIRED_INTERCHAIN_GAS_PAYMENT, TRANSFER_AMOUNT);
    }

    function testRemoteTransferIsmCollateral_unpaused() public {
        uint256 balanceBefore = localToken.balanceOf(ALICE);

        vm.prank(ALICE);
        primaryToken.authorizeOperator(address(localToken), TRANSFER_AMOUNT, "");

        _performRemoteTransferNoPause(REQUIRED_INTERCHAIN_GAS_PAYMENT, TRANSFER_AMOUNT);
        uint256 balanceAfter = localToken.balanceOf(ALICE);
        assertEq(balanceAfter, balanceBefore - TRANSFER_AMOUNT);
    }

    function testTransferToCollateralRemotePaused() public {
        vm.prank(ALICE);
        primaryToken.authorizeOperator(address(localToken), TRANSFER_AMOUNT, "");
        _performTransferToCollateralRemotePaused(REQUIRED_INTERCHAIN_GAS_PAYMENT, TRANSFER_AMOUNT);
    }

    function testTransferToCollateralLocalPaused() public {
        _performTransferToCollateralLocalPaused(REQUIRED_INTERCHAIN_GAS_PAYMENT, TRANSFER_AMOUNT);
    }

    function testNoCircuitBreakerDoesNotCauseRevert() public {
        // vm.prank(address(this));
        HypLSP7CollateralPausable lsp7CollateralNoFreezer =
            new HypLSP7CollateralPausable(address(localToken), SCALE_SYNTHETIC, address(localMailbox));
        lsp7CollateralNoFreezer.initialize(address(noopHook), address(testIsm), WARP_ROUTE_OWNER);

        bytes memory _message = TokenMessage.format(BOB.addressToBytes32(), TRANSFER_AMOUNT, "");

        localMailbox.testHandle(
            DESTINATION, address(remoteToken).addressToBytes32(), address(localToken).addressToBytes32(), _message
        );
    }
}
