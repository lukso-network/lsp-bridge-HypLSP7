// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// test utilities
import { Test } from "forge-std/src/Test.sol";
import { formatHyperlaneMessage } from "./Utils.sol";

// 📬 Hyperlane testing environnement
/// @dev See https://docs.hyperlane.xyz/docs/guides/developer-tips/unit-testing

// - Mock test contracts
import { TestMailbox } from "@hyperlane-xyz/core/contracts/test/TestMailbox.sol";
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";
import { TestInterchainGasPaymaster } from "@hyperlane-xyz/core/contracts/test/TestInterchainGasPaymaster.sol";

// - Hyperlane types and modules
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import { GasRouter } from "@hyperlane-xyz/core/contracts/client/GasRouter.sol";

// - Hyperlane libraries
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";
import { TokenMessage } from "@hyperlane-xyz/core/contracts/token/libs/TokenMessage.sol";

// Mock contracts to test
// TODO: these should be changed depending on the direction (ERC20 on Ethereum, lSP7 on LUKSO)
import { LSP7Mock } from "./LSP7Mock.sol";
import { HypLSP7 } from "../../src/HypLSP7.sol";

/// @dev TODO: write basic description of this test setup
abstract contract HypTokenTest is Test {
    using TypeCasts for address;

    // origin chain
    // ---------------------------
    uint32 internal constant ORIGIN = 11;
    TestMailbox internal localMailbox;
    TokenRouter internal localToken; // TODO: rename to originToken

    // destination chain
    // ---------------------------
    uint32 internal constant DESTINATION = 12;
    TestMailbox internal remoteMailbox;
    HypLSP7 internal remoteToken;

    // token being bridged
    // TODO: initialization of this token should be moved in the HypLSP7Test `setUp()` function
    // ---------------------------
    LSP7Mock internal primaryToken;
    string internal constant NAME = "HyperlaneInu";
    string internal constant SYMBOL = "HYP";

    // warp route parameters
    // ---------------------------
    TestPostDispatchHook internal noopHook;
    TestInterchainGasPaymaster internal interchainGasPaymaster;

    address internal immutable WARP_ROUTE_OWNER = makeAddr("warp route owner");
    uint8 internal constant DECIMALS = 18;
    uint256 internal constant TOTAL_SUPPLY = 1_000_000e18;
    uint256 internal constant GAS_LIMIT = 10_000;
    uint256 internal constant SCALE_SYNTHETIC = 1;

    // Interchain Gas Payment amount required to performed remote transfers (initialized in setUp).
    // solhint-disable-next-line var-name-mixedcase
    uint256 internal REQUIRED_INTERCHAIN_GAS_PAYMENT;

    // constants used for testing
    // ---------------------------
    address internal immutable ALICE = makeAddr("alice");
    address internal immutable BOB = makeAddr("bob");
    uint256 internal constant TRANSFER_AMOUNT = 100e18;

    function setUp() public virtual {
        // 1. deploy the initial token that we will bridge from the origin chainAdd commentMore actions
        // (in production this is assumed that this token already exists)
        // TODO: to be moved inside the `HypLSP7Test` suite
        primaryToken = new LSP7Mock(NAME, SYMBOL, address(this), TOTAL_SUPPLY);

        // 2. setup the Hyperlane core contracts on the origin chain
        localMailbox = new TestMailbox(ORIGIN);

        noopHook = new TestPostDispatchHook();
        localMailbox.setDefaultHook(address(noopHook));
        localMailbox.setRequiredHook(address(noopHook));

        REQUIRED_INTERCHAIN_GAS_PAYMENT = noopHook.quoteDispatch("", "");
        interchainGasPaymaster = new TestInterchainGasPaymaster();

        // setup the destination chain
        // TODO: shouldn't we setup the ISM here?
        remoteMailbox = new TestMailbox(DESTINATION);

        // initialize the warp route
        // TODO: this should be moved to the `HypLSP7Test` suite depending if we use the Pausable version or not
        remoteToken = new HypLSP7(DECIMALS, SCALE_SYNTHETIC, address(remoteMailbox));
        remoteToken.initialize(TOTAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), WARP_ROUTE_OWNER);

        vm.deal(ALICE, 125_000);
    }

    function _enrollRemoteTokenRouter() internal {
        vm.prank(WARP_ROUTE_OWNER);
        remoteToken.enrollRemoteRouter(ORIGIN, address(localToken).addressToBytes32());
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
        vm.prank(WARP_ROUTE_OWNER);
        localToken.setHook(address(interchainGasPaymaster));

        TokenRouter.GasRouterConfig[] memory config = new TokenRouter.GasRouterConfig[](1);
        config[0] = GasRouter.GasRouterConfig({ domain: DESTINATION, gas: GAS_LIMIT });

        vm.prank(WARP_ROUTE_OWNER);
        localToken.setDestinationGas(config);
    }

    function _performRemoteTransfer(uint256 _msgValue, uint256 _amount) internal {
        vm.prank(ALICE);

        localToken.transferRemote{ value: _msgValue }(DESTINATION, BOB.addressToBytes32(), _amount);

        vm.expectEmit(true, true, false, true);

        emit TokenRouter.ReceivedTransferRemote(ORIGIN, BOB.addressToBytes32(), _amount);
        _processTransfers(BOB, _amount);

        assertEq(remoteToken.balanceOf(BOB), _amount);
    }

    function _performRemoteTransferAndGas(uint256 _msgValue, uint256 _amount, uint256 _gasOverhead) internal {
        uint256 ethBalance = ALICE.balance;

        _performRemoteTransfer(_msgValue + _gasOverhead, _amount);

        assertEq(ALICE.balance, ethBalance - REQUIRED_INTERCHAIN_GAS_PAYMENT - _gasOverhead);
    }

    function _performRemoteTransferWithEmit(uint256 _msgValue, uint256 _amount, uint256 _gasOverhead) internal {
        vm.expectEmit(true, true, false, true);
        emit TokenRouter.SentTransferRemote(DESTINATION, BOB.addressToBytes32(), _amount);
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

    function testTransfer_withHookSpecified(uint256 fee, bytes calldata metadata) public virtual {
        TestPostDispatchHook hook = new TestPostDispatchHook();
        hook.setFee(fee);

        vm.prank(ALICE);
        primaryToken.authorizeOperator(address(localToken), TRANSFER_AMOUNT, "");
        bytes32 messageId =
            _performRemoteTransferWithHook(REQUIRED_INTERCHAIN_GAS_PAYMENT, TRANSFER_AMOUNT, address(hook), metadata);
        assertTrue(hook.messageDispatched(messageId));
    }

    function testBenchmark_overheadGasUsage() public {
        vm.prank(address(localMailbox));

        // uint256 gasBefore = gasleft();
        localToken.handle(
            DESTINATION,
            address(remoteToken).addressToBytes32(),
            abi.encodePacked(BOB.addressToBytes32(), TRANSFER_AMOUNT)
        );
        // uint256 gasAfter = gasleft();
    }
}
