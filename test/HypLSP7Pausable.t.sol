// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.13;

// test utilities
import { Test } from "forge-std/src/Test.sol";
import { Vm } from "forge-std/src/Vm.sol";

/// Hyperlane testing environnement
/// @dev See https://docs.hyperlane.xyz/docs/guides/developer-tips/unit-testing
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import { TestMailbox } from "@hyperlane-xyz/core/contracts/test/TestMailbox.sol";
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";
import { TestInterchainGasPaymaster } from "@hyperlane-xyz/core/contracts/test/TestInterchainGasPaymaster.sol";
import { TestIsm } from "@hyperlane-xyz/core/contracts/test/TestIsm.sol";

import { GasRouter } from "@hyperlane-xyz/core/contracts/client/GasRouter.sol";
// import { HypNative } from "@hyperlane-xyz/core/contracts/token/HypNative.sol";

// libraries
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";
import { TokenMessage } from "@hyperlane-xyz/core/contracts/token/libs/TokenMessage.sol";

// Mocks + contracts to test
import { LSP7Mock } from "./Mocks/LSP7Mock.sol";
import { HypLSP7Pausable } from "../src/pausable/HypLSP7Pausable.sol";
import { HypLSP7CollateralPausable } from "../src/pausable/HypLSP7CollateralPausable.sol";
// import { TokenRouterPausable } from "../src/pausable/TokenRouterPausable.sol";

import { Freezable } from "../src/pausable/Freezable.sol";

import { IERC725Y } from "@erc725/smart-contracts/contracts/interfaces/IERC725Y.sol";

// constants
import { _LSP4_METADATA_KEY } from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";
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

abstract contract HypTokenPausableTest is Test {
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
    address internal FREEZER = makeAddr("freezer");
    uint256 internal REQUIRED_VALUE; // initialized in setUp

    LSP7Mock internal primaryToken;
    TokenRouter internal localToken;
    HypLSP7Pausable internal remoteToken;
    TestMailbox internal localMailbox;
    TestMailbox internal remoteMailbox;
    TestPostDispatchHook internal noopHook;
    TestInterchainGasPaymaster internal igp;
    TestIsm internal testIsm;

    event SentTransferRemote(uint32 indexed destination, bytes32 indexed recipient, uint256 amount);

    event ReceivedTransferRemote(uint32 indexed origin, bytes32 indexed recipient, uint256 amount);

    function setUp() public virtual {
        localMailbox = new TestMailbox(ORIGIN);
        remoteMailbox = new TestMailbox(DESTINATION);

        primaryToken = new LSP7Mock(NAME, SYMBOL, address(this), TOTAL_SUPPLY);

        noopHook = new TestPostDispatchHook();
        localMailbox.setDefaultHook(address(noopHook));
        localMailbox.setRequiredHook(address(noopHook));
        testIsm = new TestIsm();

        REQUIRED_VALUE = noopHook.quoteDispatch("", "");

        remoteToken = new HypLSP7Pausable(DECIMALS, address(remoteMailbox));

        (bytes32[] memory dataKeys, bytes[] memory dataValues) = _getInitDataKeysAndValues();

        remoteToken.initialize(0, NAME, SYMBOL, address(noopHook), address(testIsm), OWNER, dataKeys, dataValues);

        vm.prank(OWNER);
        remoteToken.changeFreezer(FREEZER);

        igp = new TestInterchainGasPaymaster();

        vm.deal(ALICE, 125_000);
    }

    function _enrollRemoteTokenRouter() internal {
        vm.prank(OWNER);
        remoteToken.enrollRemoteRouter(ORIGIN, address(localToken).addressToBytes32());
    }

    function _circuitBreakerPauseLocal() internal {
        Freezable _localToken = Freezable(address(localToken));
        if (!_localToken.paused()) {
            vm.prank(FREEZER);
            _localToken.pause();
        }
        assertEq(_localToken.paused(), true);
    }

    function _circuitBreakerUnpauseLocal() internal {
        Freezable _localToken = Freezable(address(localToken));
        if (_localToken.paused()) {
            vm.prank(OWNER);
            _localToken.unpause();
        }
        assertEq(_localToken.paused(), false);
    }

    function _circuitBreakerPauseRemote() internal {
        if (!remoteToken.paused()) {
            vm.prank(FREEZER);
            remoteToken.pause();
        }
        assertEq(remoteToken.paused(), true);
    }

    function _circuitBreakerUnpauseRemote() internal {
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
            ORIGIN, address(localToken).addressToBytes32(), abi.encodePacked(_recipient.addressToBytes32(), _amount)
        );
    }

    function _setCustomGasConfig() internal {
        vm.prank(OWNER);
        localToken.setHook(address(igp));

        TokenRouter.GasRouterConfig[] memory config = new TokenRouter.GasRouterConfig[](1);
        config[0] = GasRouter.GasRouterConfig({ domain: DESTINATION, gas: GAS_LIMIT });

        vm.prank(OWNER);
        localToken.setDestinationGas(config);
    }

    function _performRemoteTransfer(uint256 _msgValue, uint256 _amount) internal {
        vm.prank(ALICE);

        localToken.transferRemote{ value: _msgValue }(DESTINATION, BOB.addressToBytes32(), _amount);

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
        vm.expectEmit(true, true, false, true);
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
        messageId = localToken.transferRemote{ value: _msgValue }(
            DESTINATION, BOB.addressToBytes32(), _amount, _hookMetadata, address(_hook)
        );
        _processTransfers(BOB, _amount);
        assertEq(remoteToken.balanceOf(BOB), _amount);
    }

    function testTransfer_withHookSpecified(uint256 fee, bytes calldata metadata) public virtual {
        TestPostDispatchHook hook = new TestPostDispatchHook();
        hook.setFee(fee);

        vm.prank(ALICE);
        primaryToken.authorizeOperator(address(localToken), TRANSFER_AMOUNT, "");
        bytes32 messageId = _performRemoteTransferWithHook(REQUIRED_VALUE, TRANSFER_AMOUNT, address(hook), metadata);
        assertTrue(hook.messageDispatched(messageId));
    }

    function testBenchmark_overheadGasUsage() public {
        vm.prank(address(localMailbox));

        localToken.handle(
            DESTINATION,
            address(remoteToken).addressToBytes32(),
            abi.encodePacked(BOB.addressToBytes32(), TRANSFER_AMOUNT)
        );
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

    // This is a work around for creating a message to Mailbox.process()
    // that doesn't use Message.formatMessage because that requires calldata
    // that foundry really doesn't like
    function _formatMessage(
        uint8 _version,
        uint32 _nonce,
        uint32 _originDomain,
        bytes32 _sender,
        uint32 _destinationDomain,
        bytes32 _recipient,
        bytes memory _messageBody // uses memory instead of calldata ftw
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(_version, _nonce, _originDomain, _sender, _destinationDomain, _recipient, _messageBody);
    }

    function _prepareProcessCall(uint256 _amount) internal view returns (bytes memory) {
        // ============== WTF IS THIS ? ===========================
        // To test whether the ISM is Paused we must call
        // Mailbox.process(_metadata, _message) on the destination side
        // calling remoteToken.handle() finalizes the cross chain transfer
        // and is only called if the ISM.verify() function returns true
        // so that method cannot be used here
        bytes memory _tokenMessage = TokenMessage.format(BOB.addressToBytes32(), _amount, "");

        bytes32 remoteTokenAddress = address(remoteToken).addressToBytes32();
        bytes32 localRouter = remoteToken.routers(ORIGIN);
        bytes32 localTokenAddress = address(localToken).addressToBytes32();
        assertEq(localRouter, localTokenAddress);

        bytes memory message = _formatMessage(
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

    function _performRemoteTransferPauseRevert(uint256 _msgValue, uint256 _amount) internal {
        _circuitBreakerPauseRemote();
        vm.prank(ALICE);
        localToken.transferRemote{ value: _msgValue }(DESTINATION, BOB.addressToBytes32(), _amount);
        emit ReceivedTransferRemote(ORIGIN, BOB.addressToBytes32(), _amount);

        bytes memory _message = _prepareProcessCall(_amount);

        vm.expectRevert("Pausable: paused");
        remoteMailbox.process("", _message); // we don't need metadata
    }

    function _performRemoteTransferNoPause(uint256 _msgValue, uint256 _amount) internal {
        _circuitBreakerUnpauseRemote();

        assertEq(remoteToken.balanceOf(BOB), 0);

        vm.prank(ALICE);
        localToken.transferRemote{ value: _msgValue }(DESTINATION, BOB.addressToBytes32(), _amount);

        emit ReceivedTransferRemote(ORIGIN, BOB.addressToBytes32(), _amount);

        bytes memory _message = _prepareProcessCall(_amount);

        remoteMailbox.process("", _message); // we don't need metadata
        assertEq(remoteToken.balanceOf(BOB), _amount);
    }

    function _performTransferToSyntheticLocalPaused(uint256 _msgValue, uint256 _amount) internal {
        _circuitBreakerPauseLocal();

        assertEq(remoteToken.balanceOf(BOB), 0);
        uint256 aliceBalance = localToken.balanceOf(ALICE);

        vm.expectRevert("Pausable: paused");
        vm.prank(ALICE);
        localToken.transferRemote{ value: _msgValue }(DESTINATION, BOB.addressToBytes32(), _amount);

        assertEq(aliceBalance, localToken.balanceOf(ALICE));
    }

    function _performTransferToSyntheticRemotePaused(uint256, /* _msgValue */ uint256 _amount) internal {
        _circuitBreakerPauseRemote();

        bytes memory _message = TokenMessage.format(BOB.addressToBytes32(), _amount, "");
        vm.expectRevert("Pausable: paused");
        vm.prank(ALICE);
        remoteMailbox.testHandle(
            ORIGIN, address(localToken).addressToBytes32(), address(remoteToken).addressToBytes32(), _message
        );
    }

    function _performTransferToCollateralRemotePaused(uint256 _msgValue, uint256 _amount) internal {
        _circuitBreakerPauseRemote();

        assertEq(remoteToken.balanceOf(BOB), 0);
        uint256 aliceBalance = localToken.balanceOf(ALICE);

        vm.expectRevert("Pausable: paused");
        vm.prank(ALICE);
        remoteToken.transferRemote{ value: _msgValue }(DESTINATION, BOB.addressToBytes32(), _amount);

        assertEq(aliceBalance, localToken.balanceOf(ALICE));
    }

    function _performTransferToCollateralLocalPaused(uint256, /* _msgValue */ uint256 _amount) internal {
        _circuitBreakerPauseLocal();

        // vm.expectRevert(CircuitError.selector);
        // vm.prank(ALICE);
        // remoteToken.transferRemote{ value: _msgValue }(DESTINATION, BOB.addressToBytes32(), _amount);

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

    function setUp() public override {
        super.setUp();

        localToken = new HypLSP7Pausable(DECIMALS, address(localMailbox));
        hypLSP7Token = HypLSP7Pausable(payable(address(localToken)));

        (bytes32[] memory dataKeys, bytes[] memory dataValues) = _getInitDataKeysAndValues();

        vm.prank(OWNER);
        hypLSP7Token.initialize(
            TOTAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(testIsm), OWNER, dataKeys, dataValues
        );

        vm.prank(OWNER);
        hypLSP7Token.enrollRemoteRouter(DESTINATION, address(remoteToken).addressToBytes32());

        // from, to, amount, force, data
        vm.startPrank(OWNER);
        hypLSP7Token.transfer(OWNER, ALICE, 1000e18, true, "");
        hypLSP7Token.changeFreezer(FREEZER);
        vm.stopPrank();

        _enrollRemoteTokenRouter();
    }

    function testInitialize_revert_ifAlreadyInitialized() public {
        (bytes32[] memory dataKeys, bytes[] memory dataValues) = _getInitDataKeysAndValues();

        vm.expectRevert("Initializable: contract is already initialized");
        hypLSP7Token.initialize(TOTAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), OWNER, dataKeys, dataValues);
    }

    function testLSP4MetadataIsSet() public view {
        assertEq(hypLSP7Token.getData(_LSP4_METADATA_KEY), SAMPLE_METADATA_BYTES);
    }

    function testEmitDataChangedEventWhenMetadataBytesProvided() public {
        vm.prank(OWNER);
        HypLSP7Pausable someHypLSP7Token = new HypLSP7Pausable(DECIMALS, address(localMailbox));

        vm.expectEmit({ checkTopic1: true, checkTopic2: false, checkTopic3: false, checkData: true });
        emit IERC725Y.DataChanged(_LSP4_METADATA_KEY, SAMPLE_METADATA_BYTES);

        (bytes32[] memory dataKeys, bytes[] memory dataValues) = _getInitDataKeysAndValues();

        someHypLSP7Token.initialize(
            TOTAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), OWNER, dataKeys, dataValues
        );
    }

    function testNoDataChangedEventEmittedIfNoMetadataBytesProvided() public {
        // Capture logs before the transaction
        vm.recordLogs();

        HypLSP7Pausable someHypLSP7Token = new HypLSP7Pausable(DECIMALS, address(localMailbox));

        (bytes32[] memory dataKeys, bytes[] memory dataValues) = (new bytes32[](0), new bytes[](0));

        // initialize token without metadata bytes
        vm.prank(OWNER);
        someHypLSP7Token.initialize(
            TOTAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), OWNER, dataKeys, dataValues
        );

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
        vm.prank(OWNER);
        remoteToken.enrollRemoteRouter(ORIGIN, address(localToken).addressToBytes32());
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
    /**
     * Deprecated
     */
    // function testRemoteTransfer_paused() public {
    //     _performRemoteTransferPauseRevert(REQUIRED_VALUE, TRANSFER_AMOUNT);
    // }

    function testRemoteTransfer_unpaused() public {
        _performRemoteTransferNoPause(REQUIRED_VALUE, TRANSFER_AMOUNT);
    }

    function testRemoteTransferToSyntheticLocalPaused() public {
        _performTransferToSyntheticLocalPaused(REQUIRED_VALUE, TRANSFER_AMOUNT);
    }

    function testTransferToSyntheticRemotePaused() public {
        _performTransferToSyntheticRemotePaused(REQUIRED_VALUE, TRANSFER_AMOUNT);
    }
}

contract HypLSP7CollateralPausableTest is HypTokenPausableTest {
    using TypeCasts for address;

    HypLSP7CollateralPausable internal lsp7Collateral;

    function setUp() public override {
        super.setUp();

        localToken = new HypLSP7CollateralPausable(address(primaryToken), address(localMailbox));

        lsp7Collateral = HypLSP7CollateralPausable(address(localToken));

        lsp7Collateral.initialize(address(noopHook), address(testIsm), OWNER);

        vm.startPrank(OWNER);
        lsp7Collateral.enrollRemoteRouter(DESTINATION, address(remoteToken).addressToBytes32());
        lsp7Collateral.changeFreezer(FREEZER);
        vm.stopPrank();

        primaryToken.transfer(address(this), address(localToken), 1000e18, true, "");

        primaryToken.transfer(address(this), ALICE, 1000e18, true, "");

        _enrollRemoteTokenRouter();
    }

    function test_constructor_revert_ifInvalidToken() public {
        vm.expectRevert("HypLSP7Collateral: invalid token");
        new HypLSP7CollateralPausable(address(0), address(localMailbox));
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

    function testTransferToCollateral_paused() public {
        vm.prank(ALICE);
        primaryToken.authorizeOperator(address(localToken), TRANSFER_AMOUNT, "");
        _performRemoteTransferPauseRevert(REQUIRED_VALUE, TRANSFER_AMOUNT);
    }

    function testRemoteTransferIsmCollateral_unpaused() public {
        uint256 balanceBefore = localToken.balanceOf(ALICE);
        vm.prank(ALICE);
        primaryToken.authorizeOperator(address(localToken), TRANSFER_AMOUNT, "");

        _performRemoteTransferNoPause(REQUIRED_VALUE, TRANSFER_AMOUNT);
        uint256 balanceAfter = localToken.balanceOf(ALICE);
        assertEq(balanceAfter, balanceBefore - TRANSFER_AMOUNT);
    }

    function testTransferToCollateralRemotePaused() public {
        vm.prank(ALICE);
        primaryToken.authorizeOperator(address(localToken), TRANSFER_AMOUNT, "");
        _performTransferToCollateralRemotePaused(REQUIRED_VALUE, TRANSFER_AMOUNT);
    }

    function testTransferToCollateralLocalPaused() public {
        _performTransferToCollateralLocalPaused(REQUIRED_VALUE, TRANSFER_AMOUNT);
    }

    function testNoCircuitBreakerDoesNotCauseRevert() public {
        HypLSP7CollateralPausable lsp7CollateralNoFreezer =
            new HypLSP7CollateralPausable(address(localToken), address(localMailbox));
        lsp7CollateralNoFreezer.initialize(address(noopHook), address(testIsm), OWNER);

        bytes memory _message = TokenMessage.format(BOB.addressToBytes32(), TRANSFER_AMOUNT, "");

        localMailbox.testHandle(
            DESTINATION, address(remoteToken).addressToBytes32(), address(localToken).addressToBytes32(), _message
        );
    }
}
