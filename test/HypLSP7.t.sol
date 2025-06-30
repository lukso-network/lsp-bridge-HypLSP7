// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.13;

// test utilities
import { Vm } from "forge-std/src/Vm.sol";
import { HypTokenTest } from "./HypTokenTest.sol";

// Hyperlane testing environnement

// - Mock test contracts
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";

// - Hyperlane types and modules
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";

// Mocks + contracts to test
import { HypNative } from "@hyperlane-xyz/core/contracts/token/HypNative.sol";
import { LSP7Mock } from "./Mocks/LSP7Mock.sol";
import { HypLSP7 } from "../src/HypLSP7.sol";
import { HypLSP7Collateral } from "../src/HypLSP7Collateral.sol";
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

// errors
import {
    LSP4TokenNameNotEditable,
    LSP4TokenSymbolNotEditable,
    LSP4TokenTypeNotEditable
} from "@lukso/lsp4-contracts/contracts/LSP4Errors.sol";
import { ERC725Y_DataKeysValuesLengthMismatch } from "@erc725/smart-contracts/contracts/errors.sol";

contract HypLSP7Test is HypTokenTest {
    HypLSP7 internal hypLSP7Token;

    function setUp() public override {
        super.setUp();

        localToken = new HypLSP7(DECIMALS, SCALE_SYNTHETIC, address(localMailbox));
        hypLSP7Token = HypLSP7(payable(address(localToken)));

        vm.prank(OWNER);
        (bytes32[] memory dataKeys, bytes[] memory dataValues) = _getInitDataKeysAndValues();
        hypLSP7Token.initialize(TOTAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), OWNER, dataKeys, dataValues);

        vm.prank(OWNER);
        hypLSP7Token.enrollRemoteRouter(DESTINATION, TypeCasts.addressToBytes32(address(remoteToken)));

        // from, to, amount, force, data
        vm.prank(OWNER);
        hypLSP7Token.transfer(OWNER, ALICE, 1000e18, true, "");

        _enrollRemoteTokenRouter();
    }

    function test_Initialize_RevertIfAlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        (bytes32[] memory dataKeys, bytes[] memory dataValues) = _getInitDataKeysAndValues();
        hypLSP7Token.initialize(TOTAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), OWNER, dataKeys, dataValues);
    }

    function test_Initialize_RevertIfDataKeysAndValuesLengthMissmatch() public {
        // Capture logs before the transaction
        vm.recordLogs();

        HypLSP7 someHypLSP7Token = new HypLSP7(DECIMALS, SCALE_SYNTHETIC, address(localMailbox));

        // initialize token without metadata bytes
        vm.prank(OWNER);
        bytes32[] memory dataKeys = new bytes32[](1);
        dataKeys[0] = _LSP4_METADATA_KEY;
        bytes[] memory dataValues = new bytes[](0);

        vm.expectRevert(ERC725Y_DataKeysValuesLengthMismatch.selector);
        someHypLSP7Token.initialize(
            TOTAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), OWNER, dataKeys, dataValues
        );
    }

    function test_SetData_ChangeTokenName_Reverts(bytes memory name) public {
        vm.prank(OWNER);
        vm.expectRevert(LSP4TokenNameNotEditable.selector);
        hypLSP7Token.setData(_LSP4_TOKEN_NAME_KEY, name);
    }

    function test_SetData_ChangeTokenSymbol_Reverts(bytes memory name) public {
        vm.prank(OWNER);
        vm.expectRevert(LSP4TokenSymbolNotEditable.selector);
        hypLSP7Token.setData(_LSP4_TOKEN_SYMBOL_KEY, name);
    }

    function test_SetData_ChangeTokenType_Reverts(bytes memory name) public {
        vm.prank(OWNER);
        vm.expectRevert(LSP4TokenTypeNotEditable.selector);
        hypLSP7Token.setData(_LSP4_TOKEN_TYPE_KEY, name);
    }

    function testInitDataKeysAreSet() public view {
        (bytes32[] memory dataKeys, bytes[] memory dataValues) = _getInitDataKeysAndValues();

        for (uint256 index = 0; index < dataKeys.length; index++) {
            vm.assertEq(hypLSP7Token.getData(dataKeys[index]), dataValues[index]);
        }
    }

    function testEmitDataChangedEventWhenMetadataBytesProvided() public {
        vm.prank(OWNER);
        HypLSP7 someHypLSP7Token = new HypLSP7(DECIMALS, SCALE_SYNTHETIC, address(localMailbox));

        vm.expectEmit({ checkTopic1: true, checkTopic2: false, checkTopic3: false, checkData: true });
        emit IERC725Y.DataChanged(_LSP4_METADATA_KEY, SAMPLE_METADATA_BYTES);

        (bytes32[] memory dataKeys, bytes[] memory dataValues) = _getInitDataKeysAndValues();
        someHypLSP7Token.initialize(
            TOTAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), OWNER, dataKeys, dataValues
        );
    }

    function testNoDataChangedEventEmittedIfNoDataKeysValuesProvided() public {
        // Capture logs before the transaction
        vm.recordLogs();

        HypLSP7 someHypLSP7Token = new HypLSP7(DECIMALS, SCALE_SYNTHETIC, address(localMailbox));

        // initialize token without setting any additional data key / value pairs
        vm.prank(OWNER);
        bytes32[] memory dataKeys = new bytes32[](0);
        bytes[] memory dataValues = new bytes[](0);
        someHypLSP7Token.initialize(
            TOTAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), OWNER, dataKeys, dataValues
        );

        // Search all the logs
        Vm.Log[] memory emittedEvents = vm.getRecordedLogs();

        for (uint256 i = 0; i < emittedEvents.length; i++) {
            // Check that no `DataChanged` event was emitted
            // except for the ones set by `LSP4DigitalAssetMetadata` contract in the inheritance
            if (bytes32(emittedEvents[i].topics[0]) == IERC725Y.DataChanged.selector) {
                bool isLSP4SupportedStandardUpdate = emittedEvents[i].topics[1] == _LSP4_SUPPORTED_STANDARDS_KEY;
                bool isLSP4TokenNameUpdate = emittedEvents[i].topics[1] == _LSP4_TOKEN_NAME_KEY;
                bool isLSP4TokenSymbolUpdate = emittedEvents[i].topics[1] == _LSP4_TOKEN_SYMBOL_KEY;
                bool isLSP4TokenTypeUpdate = emittedEvents[i].topics[1] == _LSP4_TOKEN_TYPE_KEY;

                assertTrue(
                    isLSP4SupportedStandardUpdate || isLSP4TokenNameUpdate || isLSP4TokenSymbolUpdate
                        || isLSP4TokenTypeUpdate,
                    "No DataChanged event should have been emitted except for the data keys set in `LSP4DigitalAssetMetadata` parent contract"
                );
            }
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
        vm.prank(OWNER);
        remoteToken.enrollRemoteRouter(ORIGIN, TypeCasts.addressToBytes32(address(localToken)));
        uint256 balanceBefore = hypLSP7Token.balanceOf(ALICE);

        _performRemoteTransferWithEmit(REQUIRED_VALUE, TRANSFER_AMOUNT, 0);
        assertEq(hypLSP7Token.balanceOf(ALICE), balanceBefore - TRANSFER_AMOUNT);
    }

    function testRemoteTransfer_invalidAmount() public {
        vm.expectRevert();
        _performRemoteTransfer(REQUIRED_VALUE, TRANSFER_AMOUNT * 11);
        assertEq(hypLSP7Token.balanceOf(ALICE), 1000e18);
    }

    function testRemoteTransfer_withCustomGasConfig() public {
        _setCustomGasConfig();

        uint256 balanceBefore = hypLSP7Token.balanceOf(ALICE);

        _performRemoteTransferAndGas(REQUIRED_VALUE, TRANSFER_AMOUNT, GAS_LIMIT * igp.gasPrice());

        assertEq(hypLSP7Token.balanceOf(ALICE), balanceBefore - TRANSFER_AMOUNT);
    }
}

contract HypLSP7CollateralTest is HypTokenTest {
    HypLSP7Collateral internal lsp7Collateral;

    function setUp() public override {
        super.setUp();

        localToken = new HypLSP7Collateral(address(primaryToken), SCALE_SYNTHETIC, address(localMailbox));

        lsp7Collateral = HypLSP7Collateral(address(localToken));

        lsp7Collateral.initialize(address(noopHook), address(0), OWNER);

        vm.prank(OWNER);
        lsp7Collateral.enrollRemoteRouter(DESTINATION, TypeCasts.addressToBytes32(address(remoteToken)));

        primaryToken.transfer(address(this), address(localToken), 1000e18, true, "");

        primaryToken.transfer(address(this), ALICE, 1000e18, true, "");

        _enrollRemoteTokenRouter();
    }

    function test_constructor_revert_ifInvalidToken() public {
        vm.expectRevert("HypLSP7Collateral: invalid token");
        new HypLSP7Collateral(address(0), SCALE_SYNTHETIC, address(localMailbox));
    }

    function testRemoteTransfer() public {
        uint256 balanceBefore = localToken.balanceOf(ALICE);

        vm.prank(ALICE);
        primaryToken.authorizeOperator(address(localToken), TRANSFER_AMOUNT, "");

        _performRemoteTransferWithEmit(REQUIRED_VALUE, TRANSFER_AMOUNT, 0);
        assertEq(localToken.balanceOf(ALICE), balanceBefore - TRANSFER_AMOUNT);
    }

    function testRemoteTransfer_invalidAllowance() public {
        vm.expectRevert();
        _performRemoteTransfer(REQUIRED_VALUE, TRANSFER_AMOUNT);
        assertEq(localToken.balanceOf(ALICE), 1000e18);
    }

    function testRemoteTransfer_withCustomGasConfig() public {
        _setCustomGasConfig();

        uint256 balanceBefore = localToken.balanceOf(ALICE);

        vm.prank(ALICE);
        primaryToken.authorizeOperator(address(localToken), TRANSFER_AMOUNT, "");
        _performRemoteTransferAndGas(REQUIRED_VALUE, TRANSFER_AMOUNT, GAS_LIMIT * igp.gasPrice());
        assertEq(localToken.balanceOf(ALICE), balanceBefore - TRANSFER_AMOUNT);
    }
}

contract HypNativeTest is HypTokenTest {
    HypNative internal nativeToken;
    // parameter used for native tokens that use different number of decimals than 1e18
    uint256 constant SCALE_NATIVE = 1;

    function setUp() public override {
        super.setUp();

        localToken = new HypNative(SCALE_NATIVE, address(localMailbox));
        nativeToken = HypNative(payable(address(localToken)));

        nativeToken.initialize(address(noopHook), address(0), OWNER);

        vm.prank(OWNER);
        nativeToken.enrollRemoteRouter(DESTINATION, TypeCasts.addressToBytes32(address(remoteToken)));

        vm.deal(address(localToken), 1000e18);
        vm.deal(ALICE, 1000e18);

        _enrollRemoteTokenRouter();
    }

    function testTransfer_withHookSpecified(uint256 fee, bytes calldata metadata) public override {
        TestPostDispatchHook hook = new TestPostDispatchHook();
        hook.setFee(fee);

        uint256 value = REQUIRED_VALUE + TRANSFER_AMOUNT;

        vm.prank(ALICE);
        primaryToken.authorizeOperator(address(localToken), TRANSFER_AMOUNT, "");
        bytes32 messageId = _performRemoteTransferWithHook(value, TRANSFER_AMOUNT, address(hook), metadata);
        assertTrue(hook.messageDispatched(messageId));
    }

    function testRemoteTransfer() public {
        _performRemoteTransferWithEmit(REQUIRED_VALUE, TRANSFER_AMOUNT, TRANSFER_AMOUNT);
    }

    function testRemoteTransfer_invalidAmount() public {
        vm.expectRevert("Native: amount exceeds msg.value");
        _performRemoteTransfer(REQUIRED_VALUE + TRANSFER_AMOUNT, TRANSFER_AMOUNT * 10);
        assertEq(localToken.balanceOf(ALICE), 1000e18);
    }

    function testRemoteTransfer_withCustomGasConfig() public {
        _setCustomGasConfig();

        _performRemoteTransferAndGas(REQUIRED_VALUE, TRANSFER_AMOUNT, TRANSFER_AMOUNT + GAS_LIMIT * igp.gasPrice());
    }

    function test_transferRemote_reverts_whenAmountExceedsValue(uint256 nativeValue) public {
        vm.assume(nativeValue < address(this).balance);

        address recipient = address(0xdeadbeef);
        bytes32 bRecipient = TypeCasts.addressToBytes32(recipient);
        vm.expectRevert("Native: amount exceeds msg.value");
        nativeToken.transferRemote{ value: nativeValue }(DESTINATION, bRecipient, nativeValue + 1);

        vm.expectRevert("Native: amount exceeds msg.value");
        nativeToken.transferRemote{ value: nativeValue }(
            DESTINATION, bRecipient, nativeValue + 1, bytes(""), address(0)
        );
    }
}
