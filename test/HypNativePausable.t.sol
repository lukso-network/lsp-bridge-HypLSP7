// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.13;

// test utilities
import { Test } from "forge-std/src/Test.sol";
import { Vm } from "forge-std/src/Vm.sol";
import { formatHyperlaneMessage } from "./helpers/utils.sol";

/// Hyperlane testing environnement
/// @dev See https://docs.hyperlane.xyz/docs/guides/developer-tips/unit-testing
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import { TestMailbox } from "@hyperlane-xyz/core/contracts/test/TestMailbox.sol";
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";
import { TestIsm } from "@hyperlane-xyz/core/contracts/test/TestIsm.sol";

import { TestInterchainGasPaymaster } from "@hyperlane-xyz/core/contracts/test/TestInterchainGasPaymaster.sol";
import { GasRouter } from "@hyperlane-xyz/core/contracts/client/GasRouter.sol";
// import { HypNative } from "@hyperlane-xyz/core/contracts/token/HypNative.sol";

// libraries
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";
import { TokenMessage } from "@hyperlane-xyz/core/contracts/token/libs/TokenMessage.sol";

// constants
import { _INTERFACEID_LSP0 } from "@lukso/lsp0-contracts/contracts/LSP0Constants.sol";
import {
    _LSP4_CREATORS_ARRAY_KEY,
    _LSP4_CREATORS_MAP_KEY_PREFIX,
    _LSP4_METADATA_KEY
} from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";

// LUKSO
import { HypLSP7Pausable } from "../src/pausable/HypLSP7Pausable.sol";
import { HypNativePausable } from "../src/pausable/HypNativePausable.sol";

abstract contract HypTokenTest is Test {
    using TypeCasts for address;

    uint32 internal constant ORIGIN = 11;
    uint32 internal constant DESTINATION = 12;
    uint8 internal constant DECIMALS = 18;
    uint256 internal constant TOTAL_SUPPLY = 1_000_000e18;
    uint256 internal constant GAS_LIMIT = 10_000;
    uint256 internal constant TRANSFER_AMOUNT = 100e18;
    string internal constant NAME = "HyperlaneInu";
    string internal constant SYMBOL = "HYP";
    bytes internal constant SAMPLE_METADATA_BYTES =
        hex"00006f357c6a0020820464ddfac1bec070cc14a8daf04129871d458f2ca94368aae8391311af6361696670733a2f2f516d597231564a4c776572673670456f73636468564775676f3339706136727963455a4c6a7452504466573834554178";

    address internal ALICE = makeAddr("alice");
    address internal BOB = makeAddr("bob");
    address internal OWNER = makeAddr("owner");
    address internal FREEZER = makeAddr("circuit_breaker");
    uint256 internal REQUIRED_VALUE; // initialized in setUp

    // Native warp route
    HypNativePausable internal nativeToken;
    // parameter used for native tokens that use different number of decimals than 1e18 (e.g: Solana Sealevel with
    // 1e9 for 9 decimals)
    uint256 constant SCALE_NATIVE = 1;

    HypLSP7Pausable internal remoteToken;
    // FreezerUP internal freezerLocal;
    // FreezerUP internal freezerRemote;
    TestMailbox internal localMailbox;
    TestMailbox internal remoteMailbox;
    TestPostDispatchHook internal noopHook;
    TestIsm internal testIsm;
    TestInterchainGasPaymaster internal igp;

    event SentTransferRemote(uint32 indexed destination, bytes32 indexed recipient, uint256 amount);

    event ReceivedTransferRemote(uint32 indexed origin, bytes32 indexed recipient, uint256 amount);

    function setUp() public virtual {
        localMailbox = new TestMailbox(ORIGIN);
        remoteMailbox = new TestMailbox(DESTINATION);
        testIsm = new TestIsm();

        noopHook = new TestPostDispatchHook();
        localMailbox.setDefaultHook(address(noopHook));
        localMailbox.setRequiredHook(address(noopHook));
        localMailbox.setDefaultIsm(address(testIsm));

        remoteMailbox.setDefaultHook(address(noopHook));
        remoteMailbox.setRequiredHook(address(noopHook));
        remoteMailbox.setDefaultIsm(address(testIsm));

        REQUIRED_VALUE = noopHook.quoteDispatch("", "");

        HypNativePausable localToken = new HypNativePausable(SCALE_NATIVE, address(localMailbox));
        localToken.initialize(address(noopHook), address(0), OWNER);
        nativeToken = HypNativePausable(payable(address(localToken)));

        remoteToken = new HypLSP7Pausable(DECIMALS, SCALE_NATIVE, address(remoteMailbox));
        remoteToken.initialize(TOTAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), OWNER);

        vm.startPrank(OWNER);
        nativeToken.changeFreezer(FREEZER);
        remoteToken.changeFreezer(FREEZER);
        vm.stopPrank();

        igp = new TestInterchainGasPaymaster();

        vm.deal(ALICE, 125_000);
    }

    function _enrollRemoteTokenRouter() internal {
        vm.startPrank(OWNER);
        nativeToken.enrollRemoteRouter(DESTINATION, address(remoteToken).addressToBytes32());
        remoteToken.enrollRemoteRouter(ORIGIN, address(nativeToken).addressToBytes32());
        vm.stopPrank();
    }

    function _pauseLocal() internal {
        if (!nativeToken.paused()) {
            vm.prank(FREEZER);
            nativeToken.pause();
        }
        assertEq(nativeToken.paused(), true);
    }

    function _unpauseLocal() internal {
        if (nativeToken.paused()) {
            vm.prank(OWNER);
            nativeToken.unpause();
        }
        assertEq(nativeToken.paused(), false);
    }

    function _pauseRemote() internal {
        if (!remoteToken.paused()) {
            vm.prank(FREEZER);
            remoteToken.pause();
        }
        assertEq(remoteToken.paused(), true);
    }

    function _unpauseRemote() internal {
        if (remoteToken.paused()) {
            vm.prank(OWNER);
            remoteToken.unpause();
        }
        assertEq(remoteToken.paused(), false);
    }

    function _expectRemoteBalance(address _user, uint256 _balance) internal view {
        assertEq(remoteToken.balanceOf(_user), _balance);
    }

    function _processTransfers(address _recipient, uint256 _amount) internal {
        vm.prank(address(remoteMailbox));
        remoteToken.handle(
            ORIGIN, address(nativeToken).addressToBytes32(), abi.encodePacked(_recipient.addressToBytes32(), _amount)
        );
    }

    function _setCustomGasConfig() internal {
        vm.prank(OWNER);
        nativeToken.setHook(address(igp));

        TokenRouter.GasRouterConfig[] memory config = new TokenRouter.GasRouterConfig[](1);
        config[0] = GasRouter.GasRouterConfig({ domain: DESTINATION, gas: GAS_LIMIT });

        vm.prank(OWNER);
        nativeToken.setDestinationGas(config);
    }

    function _performRemoteTransfer(uint256 _msgValue, uint256 _amount) internal {
        vm.prank(ALICE);

        nativeToken.transferRemote{ value: _msgValue }(DESTINATION, BOB.addressToBytes32(), _amount);

        vm.expectEmit(true, true, false, true);

        emit ReceivedTransferRemote(ORIGIN, BOB.addressToBytes32(), _amount);
        _processTransfers(BOB, _amount);

        assertEq(remoteToken.balanceOf(BOB), _amount);
    }

    function _performRemoteTransferAndGas(uint256 _msgValue, uint256 _amount, uint256 _gasOverhead) internal {
        uint256 ethBalance = ALICE.balance;

        _performRemoteTransfer(_msgValue + _gasOverhead, _amount);

        assertEq(ALICE.balance, ethBalance - REQUIRED_VALUE - _gasOverhead);
    }

    function _performRemoteTransferWithEmit(uint256 _msgValue, uint256 _amount, uint256 _gasOverhead) internal {
        vm.expectEmit(true, true, true, true);
        emit SentTransferRemote(DESTINATION, BOB.addressToBytes32(), _amount);
        _performRemoteTransferAndGas(_msgValue, _amount, _gasOverhead);
    }

    function _performRemoteTransferWithHook(
        uint256 _msgValue,
        uint256 _amount,
        address _hook,
        bytes memory _hookMetadata
    )
        internal
        returns (bytes32 messageId)
    {
        vm.prank(ALICE);
        messageId = nativeToken.transferRemote{ value: _msgValue }(
            DESTINATION, BOB.addressToBytes32(), _amount, _hookMetadata, address(_hook)
        );
        _processTransfers(BOB, _amount);
        assertEq(remoteToken.balanceOf(BOB), _amount);
    }

    function testTransfer_withHookSpecified(uint256 fee, bytes calldata metadata) public virtual {
        TestPostDispatchHook hook = new TestPostDispatchHook();
        hook.setFee(fee);

        // vm.prank(ALICE);
        // // primaryToken.authorizeOperator(address(localToken), TRANSFER_AMOUNT, "");
        bytes32 messageId = _performRemoteTransferWithHook(REQUIRED_VALUE, TRANSFER_AMOUNT, address(hook), metadata);
        assertTrue(hook.messageDispatched(messageId));
    }

    function testBenchmark_overheadGasUsage() public {
        vm.prank(address(localMailbox));

        uint256 gasBefore = gasleft();
        nativeToken.handle(
            DESTINATION,
            address(remoteToken).addressToBytes32(),
            abi.encodePacked(BOB.addressToBytes32(), TRANSFER_AMOUNT)
        );
        uint256 gasAfter = gasleft();
    }

    function _prepareProcessCall(uint256 _amount) internal returns (bytes memory) {
        // ============== WTF IS THIS ? ===========================
        // To test whether the ISM is Paused we must call
        // Mailbox.process(_metadata, _message) on the destination side
        // calling remoteToken.handle() finalizes the cross chain transfer
        // and is only called if the ISM.verify() function returns true
        // so that method cannot be used here
        bytes memory _tokenMessage = TokenMessage.format(BOB.addressToBytes32(), _amount, "");

        bytes32 remoteTokenAddress = address(remoteToken).addressToBytes32();
        bytes32 localRouter = remoteToken.routers(ORIGIN);
        bytes32 localTokenAddress = address(nativeToken).addressToBytes32();
        assertEq(localRouter, localTokenAddress);

        bytes memory message = formatHyperlaneMessage(
            3, // _version
            1, // _nonce
            ORIGIN, // _originDomain
            localTokenAddress, // _sender is the Router of ORIGIN
            DESTINATION, // _destinationDomain
            remoteTokenAddress, // _recipient is the remote HypLSP7
            _tokenMessage //_messageBody IS instructions on how much to send to what address
        );

        return message;
    }

    // setting data keys for the following:
    // - 1 x creator in the creator array
    // - creator's info under the map key
    // - the token metadata
    function _getInitDataKeysAndValues() internal view returns (bytes32[] memory dataKeys, bytes[] memory dataValues) {
        dataKeys = new bytes32[](4);
        dataKeys[0] = _LSP4_CREATORS_ARRAY_KEY;
        dataKeys[1] = bytes32(abi.encodePacked(bytes16(_LSP4_CREATORS_ARRAY_KEY), bytes16(uint128(0))));
        dataKeys[2] = bytes32(abi.encodePacked(_LSP4_CREATORS_MAP_KEY_PREFIX, bytes2(0), bytes20(msg.sender)));
        dataKeys[3] = _LSP4_METADATA_KEY;

        dataValues = new bytes[](4);
        dataValues[0] = abi.encodePacked(bytes16(uint128(1)));
        dataValues[1] = abi.encodePacked(bytes20(msg.sender));
        dataValues[2] = abi.encodePacked(_INTERFACEID_LSP0, bytes16(uint128(0)));
        dataValues[3] = SAMPLE_METADATA_BYTES;
    }
}

contract HypNativePausableTest is HypTokenTest {
    using TypeCasts for address;

    function setUp() public override {
        super.setUp();

        vm.deal(address(nativeToken), 1000e18);
        vm.deal(ALICE, 1000e18);

        _enrollRemoteTokenRouter();
    }

    function testTransfer_withHookSpecified(uint256 fee, bytes calldata metadata) public override {
        TestPostDispatchHook hook = new TestPostDispatchHook();
        hook.setFee(fee);

        uint256 value = REQUIRED_VALUE + TRANSFER_AMOUNT;

        bytes32 messageId = _performRemoteTransferWithHook(value, TRANSFER_AMOUNT, address(hook), metadata);
        assertTrue(hook.messageDispatched(messageId));
    }

    function testRemoteTransfer() public {
        _performRemoteTransferWithEmit(REQUIRED_VALUE, TRANSFER_AMOUNT, TRANSFER_AMOUNT);
    }

    function testRemoteTransfer_invalidAmount() public {
        vm.expectRevert("Native: amount exceeds msg.value");
        _performRemoteTransfer(REQUIRED_VALUE + TRANSFER_AMOUNT, TRANSFER_AMOUNT * 10);
        assertEq(nativeToken.balanceOf(ALICE), 1000e18);
    }

    function testRemoteTransfer_withCustomGasConfig() public {
        _setCustomGasConfig();

        _performRemoteTransferAndGas(REQUIRED_VALUE, TRANSFER_AMOUNT, TRANSFER_AMOUNT + GAS_LIMIT * igp.gasPrice());
    }

    function testtransferRemote_reverts_whenAmountExceedsValue(uint256 nativeValue) public {
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

    function testPerformTransferToNativeLocalPaused() public {
        _pauseLocal();
        vm.prank(ALICE);

        bytes memory _tokenMessage = TokenMessage.format(BOB.addressToBytes32(), TRANSFER_AMOUNT, "");

        vm.expectRevert("Pausable: paused");
        localMailbox.testHandle(
            DESTINATION, address(remoteToken).addressToBytes32(), address(nativeToken).addressToBytes32(), _tokenMessage
        ); // we don't need metadata
    }

    function testPerformTransferToNativeRemotePaused() public {
        // first make sure there is synthetic tokens available to ALICE
        bytes memory _message = TokenMessage.format(ALICE.addressToBytes32(), TRANSFER_AMOUNT, "");
        remoteMailbox.testHandle(
            ORIGIN, address(nativeToken).addressToBytes32(), address(remoteToken).addressToBytes32(), _message
        );

        _pauseRemote();
        vm.prank(ALICE);
        vm.expectRevert("Pausable: paused");
        remoteToken.transferRemote(ORIGIN, BOB.addressToBytes32(), TRANSFER_AMOUNT);
    }

    function testPerformTransferToSyntheticLocalPaused() public {
        _pauseLocal();

        uint256 _msgValue = REQUIRED_VALUE + TRANSFER_AMOUNT;

        vm.prank(ALICE);
        vm.expectRevert("Pausable: paused");
        nativeToken.transferRemote{ value: _msgValue }(DESTINATION, BOB.addressToBytes32(), TRANSFER_AMOUNT);
    }

    function testPerformTransferToSyntheticRemotePaused() public {
        _pauseRemote();

        // bytes memory _message = _prepareProcessCall(_amount);
        bytes memory _tokenMessage = TokenMessage.format(BOB.addressToBytes32(), TRANSFER_AMOUNT, "");

        vm.expectRevert("Pausable: paused");
        remoteMailbox.testHandle(
            ORIGIN, address(nativeToken).addressToBytes32(), address(remoteToken).addressToBytes32(), _tokenMessage
        ); // we don't need metadata
    }

    function testPerformRemoteTransferNoPause() public {
        _unpauseLocal();
        _unpauseRemote();

        assertEq(remoteToken.balanceOf(BOB), 0);

        uint256 _msgValue = REQUIRED_VALUE + TRANSFER_AMOUNT;

        vm.prank(ALICE);
        nativeToken.transferRemote{ value: _msgValue }(DESTINATION, BOB.addressToBytes32(), TRANSFER_AMOUNT);

        emit ReceivedTransferRemote(ORIGIN, BOB.addressToBytes32(), TRANSFER_AMOUNT);

        bytes memory _message = _prepareProcessCall(TRANSFER_AMOUNT);

        remoteMailbox.process("", _message); // we don't need metadata
        assertEq(remoteToken.balanceOf(BOB), TRANSFER_AMOUNT);
    }

    function testNoCircuitBreakerDoesNotCauseRevert() public {
        vm.prank(OWNER);
        nativeToken.changeFreezer(address(0));

        bytes memory _message = TokenMessage.format(BOB.addressToBytes32(), TRANSFER_AMOUNT, "");

        localMailbox.testHandle(
            DESTINATION, address(remoteToken).addressToBytes32(), address(nativeToken).addressToBytes32(), _message
        );
    }
}
