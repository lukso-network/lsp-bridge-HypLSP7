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

/**
 * @title Hyperlane test suite setup
 *
 * @dev Set of helper functions to enable setting up the Hyperlane testing environnement, such as
 * deploying Hyperlane Mailboxes and internal functions to perform bridge transactions from
 * the origin / destination chains (triggering remote transfer on origin + handle upcoming bridge
 * transactions on destination)
 */
abstract contract HypTokenTest is Test {
    using TypeCasts for address;

    // origin chain
    // ---------------------------
    uint32 internal ORIGIN_CHAIN_ID;
    TestMailbox internal originMailbox;
    TestPostDispatchHook internal mailboxDefaultHook;
    TestPostDispatchHook internal mailboxRequiredHook;
    TokenRouter internal localToken; // TODO: rename to originToken

    // destination chain
    // ---------------------------
    uint32 internal DESTINATION_CHAIN_ID;
    TestMailbox internal destinationMailbox;
    HypLSP7 internal remoteToken;

    // warp route parameters
    // ---------------------------
    TestInterchainGasPaymaster internal interchainGasPaymaster;

    address internal immutable WARP_ROUTE_OWNER = makeAddr("warp route owner");
    uint256 internal constant GAS_LIMIT = 10_000;

    // Interchain Gas Payment amount required to performed remote transfers (initialized in setUp).
    // solhint-disable-next-line var-name-mixedcase
    uint256 internal REQUIRED_INTERCHAIN_GAS_PAYMENT;

    // constants used for testing
    // ---------------------------
    address internal immutable ALICE = makeAddr("alice");
    address internal immutable BOB = makeAddr("bob");

    function setUp() public virtual {
        assertGt(ORIGIN_CHAIN_ID, 0, "HypTokenTest: origin chain ID not configured");
        assertGt(DESTINATION_CHAIN_ID, 0, "HypTokenTest: destination chain ID not configured");

        // 1. setup the Hyperlane core contracts on the origin chain
        originMailbox = new TestMailbox({ _localDomain: ORIGIN_CHAIN_ID });

        mailboxDefaultHook = new TestPostDispatchHook();
        mailboxRequiredHook = new TestPostDispatchHook();
        originMailbox.setDefaultHook(address(mailboxDefaultHook));
        originMailbox.setRequiredHook(address(mailboxRequiredHook));

        REQUIRED_INTERCHAIN_GAS_PAYMENT = mailboxDefaultHook.quoteDispatch("", "");
        interchainGasPaymaster = new TestInterchainGasPaymaster();

        // 2. setup the destination chain
        // TODO: setup default + required hook here
        destinationMailbox = new TestMailbox({ _localDomain: DESTINATION_CHAIN_ID });

        vm.deal(ALICE, 125_000);
    }

    // TODO: ask AI for better parameters names
    function _enrollOriginTokenRouter(TokenRouter tokenRouter, address routerOnDomain) internal {
        tokenRouter.enrollRemoteRouter({
            _domain: DESTINATION_CHAIN_ID,
            _router: address(routerOnDomain).addressToBytes32()
        });
    }

    function _enrollDestinationTokenRouter(TokenRouter tokenRouter, address routerOnDomain) internal {
        tokenRouter.enrollRemoteRouter({ _domain: ORIGIN_CHAIN_ID, _router: address(routerOnDomain).addressToBytes32() });
    }

    function _setCustomGasConfig(TokenRouter tokenRouter) internal {
        vm.prank(WARP_ROUTE_OWNER);
        tokenRouter.setHook(address(interchainGasPaymaster));

        TokenRouter.GasRouterConfig[] memory config = new TokenRouter.GasRouterConfig[](1);
        config[0] = GasRouter.GasRouterConfig({ domain: DESTINATION_CHAIN_ID, gas: GAS_LIMIT });

        vm.prank(WARP_ROUTE_OWNER);
        tokenRouter.setDestinationGas(config);
    }

    // Helper functions to perform bridge transactions (= remote transfers)

    function _performBridgeTx(
        TokenRouter originTokenRouter,
        TokenRouter destinationTokenRouter,
        uint256 _msgValue,
        uint256 _amount
    )
        internal
    {
        vm.prank(ALICE);
        originTokenRouter.transferRemote{ value: _msgValue }(DESTINATION_CHAIN_ID, BOB.addressToBytes32(), _amount);

        vm.expectEmit(true, true, false, true);
        emit TokenRouter.ReceivedTransferRemote(ORIGIN_CHAIN_ID, BOB.addressToBytes32(), _amount);

        _processBridgeTxOnDestinationChain(destinationTokenRouter, originTokenRouter, BOB, _amount);
    }

    function _performBridgeTxWithCustomGasConfig(
        TokenRouter originTokenRouter,
        TokenRouter destinationTokenRouter,
        uint256 msgValue,
        uint256 amount,
        uint256 gasOverhead
    )
        internal
    {
        uint256 ethBalance = ALICE.balance;

        _performBridgeTx(originTokenRouter, destinationTokenRouter, msgValue + gasOverhead, amount);

        assertEq(ALICE.balance, ethBalance - REQUIRED_INTERCHAIN_GAS_PAYMENT - gasOverhead);
    }

    function _performBridgeTxAndCheckSentTransferRemoteEvent(
        TokenRouter originTokenRouter,
        TokenRouter destinationTokenRouter,
        uint256 _msgValue,
        uint256 _amount
    )
        // uint256 _gasOverhead
        internal
    {
        vm.expectEmit(true, true, false, true);
        emit TokenRouter.SentTransferRemote(DESTINATION_CHAIN_ID, BOB.addressToBytes32(), _amount);
        _performBridgeTx(originTokenRouter, destinationTokenRouter, _msgValue, _amount);

        // TODO: Initially, this function was called `_performRemoteTransferWithEmit` and had the `_gasOverhead`
        // parameter.
        // We could reuse this parameter to call the other function and use the `messageId` returned here for further
        // assertion.
        // _performBridgeTxWithCustomGasConfig(originTokenRouter, destinationTokenRouter, _msgValue, _amount,
        // _gasOverhead);
    }

    function _performBridgeTxWithHookSpecified(
        TokenRouter originTokenRouter,
        TokenRouter destinationTokenRouter,
        uint256 _msgValue,
        uint256 _amount,
        address _hook,
        bytes memory _hookMetadata
    )
        internal
        returns (bytes32 messageId)
    {
        assertNotEq(address(originTokenRouter), address(destinationTokenRouter));

        vm.prank(ALICE);
        messageId = originTokenRouter.transferRemote{ value: _msgValue }(
            DESTINATION_CHAIN_ID, BOB.addressToBytes32(), _amount, _hookMetadata, address(_hook)
        );

        _processBridgeTxOnDestinationChain(destinationTokenRouter, originTokenRouter, BOB, _amount);
    }

    function _processBridgeTxOnDestinationChain(
        TokenRouter destinationTokenRouter,
        TokenRouter originTokenRouter,
        address recipient,
        uint256 amount
    )
        internal
    {
        vm.prank(address(destinationMailbox));
        destinationTokenRouter.handle(
            ORIGIN_CHAIN_ID,
            address(originTokenRouter).addressToBytes32(),
            abi.encodePacked(recipient.addressToBytes32(), amount)
        );
    }

    // function _processBridgeBackTxOnSourceChain(
    //     TokenRouter originTokenRouter,
    //     TokenRouter destinationTokenRouter,
    //     address recipient,
    //     uint256 amount
    // )
    //     internal
    // {
    //     vm.prank(address(originMailbox));
    //     originTokenRouter.handle(
    //         DESTINATION_CHAIN_ID,
    //         address(destinationTokenRouter).addressToBytes32(),
    //         abi.encodePacked(recipient.addressToBytes32(), amount)
    //     );
    // }

    // TODO: move this function inside the test suites for the Pausable version of the tokens
    function _prepareProcessCall(uint256 _amount) internal view returns (bytes memory) {
        // ============== WTF IS THIS ? ===========================
        // To test whether the ISM is Paused we must call
        // Mailbox.process(_metadata, _message) on the destination side
        // calling remoteToken.handle() finalizes the cross chain transfer
        // and is only called if the ISM.verify() function returns true
        // so that method cannot be used here
        bytes memory _tokenMessage = TokenMessage.format(BOB.addressToBytes32(), _amount, "");

        bytes32 remoteTokenAddress = address(remoteToken).addressToBytes32();
        bytes32 localRouter = remoteToken.routers(ORIGIN_CHAIN_ID);
        bytes32 localTokenAddress = address(localToken).addressToBytes32();
        assertEq(localRouter, localTokenAddress);

        bytes memory message = formatHyperlaneMessage(
            3, // _version
            1, // _nonce
            ORIGIN_CHAIN_ID, // _originDomain
            localTokenAddress, // _sender is the Router of ORIGIN
            DESTINATION_CHAIN_ID, // _destinationDomain
            remoteTokenAddress, // _recipient is the remote HypLSP7
            _tokenMessage //_messageBody IS instructions on how much to send to what address
        );

        return message;
    }
}
