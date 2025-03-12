// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.13;

import { Test } from "forge-std/src/Test.sol";

/// Hyperlane testing environnement
/// @dev See https://docs.hyperlane.xyz/docs/guides/developer-tips/unit-testing
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import { TestMailbox } from "@hyperlane-xyz/core/contracts/test/TestMailbox.sol";
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";
import { TestInterchainGasPaymaster } from "@hyperlane-xyz/core/contracts/test/TestInterchainGasPaymaster.sol";
import { GasRouter } from "@hyperlane-xyz/core/contracts/client/GasRouter.sol";
import { HypNative } from "@hyperlane-xyz/core/contracts/token/HypNative.sol";
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";
import { TokenMessage } from "@hyperlane-xyz/core/contracts/token/libs/TokenMessage.sol";

// Mocks + contracts to test
import { LSP7Mock } from "./LSP7Mock.sol";
import { HypLSP7 } from "../src/HypLSP7.sol";
import { HypLSP7Collateral } from "../src/HypLSP7Collateral.sol";
import { PausableCircuitBreakerIsm } from "../src/ISM/PausableCircuitBreakerISM.sol";
import { PausableCircuitBreakerHook } from "../src/ISM/PausableCircuitBreakerHook.sol";

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

    address internal ALICE = makeAddr("alice");
    address internal BOB = makeAddr("bob");
    address internal OWNER = makeAddr("owner");
    address internal CIRCUIT_BREAKER = makeAddr("circuit_breaker");
    uint256 internal REQUIRED_VALUE; // initialized in setUp

    LSP7Mock internal primaryToken;
    TokenRouter internal localToken;
    HypLSP7 internal remoteToken;
    TestMailbox internal localMailbox;
    TestMailbox internal remoteMailbox;
    TestPostDispatchHook internal noopHook;
    TestInterchainGasPaymaster internal igp;

    PausableCircuitBreakerHook internal pausableHook;
    PausableCircuitBreakerIsm internal pausableIsm;

    event SentTransferRemote(uint32 indexed destination, bytes32 indexed recipient, uint256 amount);

    event ReceivedTransferRemote(uint32 indexed origin, bytes32 indexed recipient, uint256 amount);

    function setUp() public virtual {
        localMailbox = new TestMailbox(ORIGIN);
        remoteMailbox = new TestMailbox(DESTINATION);

        primaryToken = new LSP7Mock(NAME, SYMBOL, address(this), TOTAL_SUPPLY);

        noopHook = new TestPostDispatchHook();
        localMailbox.setDefaultHook(address(noopHook));
        localMailbox.setRequiredHook(address(noopHook));

        pausableHook = new PausableCircuitBreakerHook(OWNER);
        pausableIsm = new PausableCircuitBreakerIsm(OWNER);

        REQUIRED_VALUE = noopHook.quoteDispatch("", "");

        remoteToken = new HypLSP7(DECIMALS, address(remoteMailbox));

        remoteToken.initialize(TOTAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), OWNER);

        igp = new TestInterchainGasPaymaster();

        vm.deal(ALICE, 125_000);
    }

    function _enrollRemoteTokenRouter() internal {
        vm.prank(OWNER);
        remoteToken.enrollRemoteRouter(ORIGIN, address(localToken).addressToBytes32());
    }

    function _setupPausableIsm() internal {
        vm.prank(OWNER);
        remoteToken.setInterchainSecurityModule(address(pausableIsm));

        vm.prank(OWNER);
        pausableIsm.registerCircuitBreaker(CIRCUIT_BREAKER);
    }

    // Setting this as a different function because the hook interferes with other tests
    function _setupPausableHook() internal {
        localMailbox.setRequiredHook(address(pausableHook));

        vm.prank(OWNER);
        pausableHook.registerCircuitBreaker(CIRCUIT_BREAKER);
    }

    function _circuitBreakerPauseIsm() internal {
        if (!pausableIsm.paused()) {
            vm.prank(CIRCUIT_BREAKER);
            pausableIsm.pause();
        }
        assertEq(pausableIsm.paused(), true);
    }

    function _circuitBreakerUnpauseIsm() internal {
        if (pausableIsm.paused()) {
            vm.prank(OWNER);
            pausableIsm.unpause();
        }
        assertEq(pausableIsm.paused(), false);
    }

    function _circuitBreakerPauseHook() internal {
        if (!pausableHook.paused()) {
            vm.prank(CIRCUIT_BREAKER);
            pausableHook.pause();
        }
        assertEq(pausableHook.paused(), true);
    }

    function _circuitBreakerUnpauseHook() internal {
        if (pausableHook.paused()) {
            vm.prank(OWNER);
            pausableHook.unpause();
        }
        assertEq(pausableHook.paused(), false);
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

        uint256 gasBefore = gasleft();
        localToken.handle(
            DESTINATION,
            address(remoteToken).addressToBytes32(),
            abi.encodePacked(BOB.addressToBytes32(), TRANSFER_AMOUNT)
        );
        uint256 gasAfter = gasleft();
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
        _circuitBreakerPauseIsm();
        vm.prank(ALICE);
        localToken.transferRemote{ value: _msgValue }(DESTINATION, BOB.addressToBytes32(), _amount);
        emit ReceivedTransferRemote(ORIGIN, BOB.addressToBytes32(), _amount);

        bytes memory _message = _prepareProcessCall(_amount);

        vm.expectRevert("Pausable: paused");
        remoteMailbox.process("", _message); // we don't need metadata
    }

    function _performRemoteTransferNoPause(uint256 _msgValue, uint256 _amount) internal {
        _circuitBreakerUnpauseIsm();

        assertEq(remoteToken.balanceOf(BOB), 0);

        vm.prank(ALICE);
        localToken.transferRemote{ value: _msgValue }(DESTINATION, BOB.addressToBytes32(), _amount);

        emit ReceivedTransferRemote(ORIGIN, BOB.addressToBytes32(), _amount);

        bytes memory _message = _prepareProcessCall(_amount);

        remoteMailbox.process("", _message); // we don't need metadata
        assertEq(remoteToken.balanceOf(BOB), _amount);
    }

    function _performRemoteTransferWithPausedHook(uint256 _msgValue, uint256 _amount) internal {
        _setupPausableHook();
        _circuitBreakerPauseHook();

        assertEq(remoteToken.balanceOf(BOB), 0);
        uint256 aliceBalance = localToken.balanceOf(ALICE);

        vm.expectRevert("Pausable: paused");
        vm.prank(ALICE);
        localToken.transferRemote{ value: _msgValue }(DESTINATION, BOB.addressToBytes32(), _amount);

        assertEq(aliceBalance, localToken.balanceOf(ALICE));
    }
}

contract HypLSP7Test is HypTokenTest {
    using TypeCasts for address;

    HypLSP7 internal hypLSP7Token;

    function setUp() public override {
        super.setUp();

        localToken = new HypLSP7(DECIMALS, address(localMailbox));
        hypLSP7Token = HypLSP7(payable(address(localToken)));

        vm.prank(OWNER);
        hypLSP7Token.initialize(TOTAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), OWNER);

        vm.prank(OWNER);
        hypLSP7Token.enrollRemoteRouter(DESTINATION, address(remoteToken).addressToBytes32());

        // from, to, amount, force, data
        vm.prank(OWNER);
        hypLSP7Token.transfer(OWNER, ALICE, 1000e18, true, "");

        _enrollRemoteTokenRouter();
        _setupPausableIsm();
    }

    function testInitialize_revert_ifAlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        hypLSP7Token.initialize(TOTAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), OWNER);
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

    function testRemoteTransfer_paused() public {
        _performRemoteTransferPauseRevert(REQUIRED_VALUE, TRANSFER_AMOUNT);
    }

    function testRemoteTransfer_unpaused() public {
        _performRemoteTransferNoPause(REQUIRED_VALUE, TRANSFER_AMOUNT);
    }

    function testRemoteTransfer_pausedHook() public {
        _performRemoteTransferWithPausedHook(REQUIRED_VALUE, TRANSFER_AMOUNT);
    }
}

contract HypLSP7CollateralTest is HypTokenTest {
    using TypeCasts for address;

    HypLSP7Collateral internal lsp7Collateral;

    function setUp() public override {
        super.setUp();

        localToken = new HypLSP7Collateral(address(primaryToken), address(localMailbox));

        lsp7Collateral = HypLSP7Collateral(address(localToken));

        lsp7Collateral.initialize(address(noopHook), address(0), OWNER);

        vm.prank(OWNER);
        lsp7Collateral.enrollRemoteRouter(DESTINATION, address(remoteToken).addressToBytes32());

        primaryToken.transfer(address(this), address(localToken), 1000e18, true, "");

        primaryToken.transfer(address(this), ALICE, 1000e18, true, "");

        _enrollRemoteTokenRouter();
        _setupPausableIsm();
    }

    function test_constructor_revert_ifInvalidToken() public {
        vm.expectRevert("HypLSP7Collateral: invalid token");
        new HypLSP7Collateral(address(0), address(localMailbox));
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

    function testRemoteTransferIsmCollateral_paused() public {
        uint256 balanceBefore = localToken.balanceOf(ALICE);

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

    function testRemoteTransferCollateral_pausedHook() public {
        vm.prank(ALICE);
        primaryToken.authorizeOperator(address(localToken), TRANSFER_AMOUNT, "");
        _performRemoteTransferWithPausedHook(REQUIRED_VALUE, TRANSFER_AMOUNT);
    }
}

contract HypNativeTest is HypTokenTest {
    using TypeCasts for address;

    HypNative internal nativeToken;

    function setUp() public override {
        super.setUp();

        localToken = new HypNative(address(localMailbox));
        nativeToken = HypNative(payable(address(localToken)));

        nativeToken.initialize(address(noopHook), address(0), OWNER);

        vm.prank(OWNER);
        nativeToken.enrollRemoteRouter(DESTINATION, address(remoteToken).addressToBytes32());

        vm.deal(address(localToken), 1000e18);
        vm.deal(ALICE, 1000e18);

        _enrollRemoteTokenRouter();
        _setupPausableIsm();
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

    function testRemoteTransfer_paused() public {
        _performRemoteTransferPauseRevert(REQUIRED_VALUE + TRANSFER_AMOUNT, TRANSFER_AMOUNT);
    }

    function testRemoteTransfer_unpaused() public {
        _performRemoteTransferNoPause(REQUIRED_VALUE + TRANSFER_AMOUNT, TRANSFER_AMOUNT);
    }

    function testRemoteTransfer_pausedHook() public {
        _performRemoteTransferWithPausedHook(REQUIRED_VALUE + TRANSFER_AMOUNT, TRANSFER_AMOUNT);
    }
}
