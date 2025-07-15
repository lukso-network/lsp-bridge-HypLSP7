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
    TestPostDispatchHook internal originMailboxDefaultHook;
    TestPostDispatchHook internal originMailboxRequiredtHook;

    // collateral contract locking tokens (MUST be set in contract inheritting from `HypTokenTest`)
    TokenRouter internal originTokenRouter;

    // destination chain
    // ---------------------------
    uint32 internal DESTINATION_CHAIN_ID;
    TestMailbox internal destinationMailbox;
    TestPostDispatchHook internal destinationMailboxDefaultHook;
    TestPostDispatchHook internal destinationMailboxRequiredtHook;

    // synthetic token (MUST be set in contract inheritting from `HypTokenTest`)
    TokenRouter internal destinationTokenRouter;

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
        assertNotEq(ORIGIN_CHAIN_ID, DESTINATION_CHAIN_ID, "HypTokenTest:");

        // 1. setup the Hyperlane core contracts on the origin chain
        originMailbox = new TestMailbox({ _localDomain: ORIGIN_CHAIN_ID });

        originMailboxDefaultHook = new TestPostDispatchHook();
        originMailboxRequiredtHook = new TestPostDispatchHook();
        originMailbox.setDefaultHook(address(originMailboxDefaultHook));
        originMailbox.setRequiredHook(address(originMailboxRequiredtHook));

        REQUIRED_INTERCHAIN_GAS_PAYMENT = originMailboxDefaultHook.quoteDispatch("", "");
        interchainGasPaymaster = new TestInterchainGasPaymaster();

        // 2. setup the destination chain
        destinationMailbox = new TestMailbox({ _localDomain: DESTINATION_CHAIN_ID });

        destinationMailboxDefaultHook = new TestPostDispatchHook();
        destinationMailboxRequiredtHook = new TestPostDispatchHook();
        destinationMailbox.setDefaultHook(address(destinationMailboxDefaultHook));
        destinationMailbox.setRequiredHook(address(destinationMailboxRequiredtHook));

        // Give native tokens to Alice for paying the interchain gas payment when bridging
        vm.deal(ALICE, 125_000);
    }

    function _enrollOriginTokenRouter() internal {
        originTokenRouter.enrollRemoteRouter({
            _domain: DESTINATION_CHAIN_ID,
            _router: address(destinationTokenRouter).addressToBytes32()
        });
    }

    function _enrollDestinationTokenRouter() internal {
        destinationTokenRouter.enrollRemoteRouter({
            _domain: ORIGIN_CHAIN_ID,
            _router: address(originTokenRouter).addressToBytes32()
        });
    }

    /// @dev Configure the `tokenRouter` contract to call the `InterchainGasPaymaster` contract
    /// as default post-dispatch hook.
    ///
    /// This will also configure the destination gas parameter when bridging to `DESTINATION_CHAIN_ID`
    /// to be a maximum `GAS_LIMIT` that can run on the destination chain.
    function _setCustomGasConfig(TokenRouter _tokenRouter) internal {
        vm.prank(WARP_ROUTE_OWNER);
        _tokenRouter.setHook(address(interchainGasPaymaster));

        TokenRouter.GasRouterConfig[] memory config = new TokenRouter.GasRouterConfig[](1);
        config[0] = GasRouter.GasRouterConfig({ domain: DESTINATION_CHAIN_ID, gas: GAS_LIMIT });

        vm.prank(WARP_ROUTE_OWNER);
        _tokenRouter.setDestinationGas(config);
    }

    // Helper functions to perform bridge transactions (= remote transfers)

    function _performBridgeTx(uint256 _msgValue, uint256 _amount) internal {
        vm.prank(ALICE);
        originTokenRouter.transferRemote{ value: _msgValue }(DESTINATION_CHAIN_ID, BOB.addressToBytes32(), _amount);

        vm.expectEmit({ emitter: address(destinationTokenRouter) });
        emit TokenRouter.ReceivedTransferRemote(ORIGIN_CHAIN_ID, BOB.addressToBytes32(), _amount);
        _processBridgeTxOnDestinationChain(BOB, _amount);
    }

    function _performBridgeTxWithCustomGasConfig(uint256 _msgValue, uint256 _amount, uint256 _gasOverhead) internal {
        _performBridgeTx(_msgValue + _gasOverhead, _amount);
    }

    function _performBridgeTxAndCheckSentTransferRemoteEvent(uint256 _msgValue, uint256 _amount) internal {
        vm.expectEmit({ emitter: address(originTokenRouter) });
        emit TokenRouter.SentTransferRemote(DESTINATION_CHAIN_ID, BOB.addressToBytes32(), _amount);
        _performBridgeTx(_msgValue, _amount);
    }

    function _performBridgeTxWithHookSpecified(
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

        _processBridgeTxOnDestinationChain(BOB, _amount);
    }

    function _processBridgeTxOnDestinationChain(address _recipient, uint256 _amount) internal {
        vm.prank(address(destinationMailbox));
        destinationTokenRouter.handle(
            ORIGIN_CHAIN_ID,
            address(originTokenRouter).addressToBytes32(),
            abi.encodePacked(_recipient.addressToBytes32(), _amount)
        );
    }

    // Other helper functions
    // --------------------

    /// @dev Prepare the call that the Hyperlane relayer should send on the destination chain.
    /// The encoded bytes returned by this function can be used as parameter to call
    /// `Mailbox.process(_metadata, _message)` on the destination chain.
    ///
    /// This is useful for testing transactions that should revert on the destination chain by:
    ///     - if the `ISM.verify(...)` function will return `false`
    ///     - if a warp route is paused (will revert when `Mailbox.process(...)` on the destination chain call
    /// `remoteToken.handle(...)`)
    function _prepareProcessCall(uint256 _amount) internal view returns (bytes memory) {
        bytes memory tokenMessage = TokenMessage.format(BOB.addressToBytes32(), _amount, "");

        bytes32 routerForOrigin = destinationTokenRouter.routers(ORIGIN_CHAIN_ID);
        bytes32 encodedOriginTokenRouterAddress = address(originTokenRouter).addressToBytes32();
        bytes32 encodedDestinationTokenRouterAddress = address(destinationTokenRouter).addressToBytes32();

        // Sanity CHECK to ensure the token router contract on the destination chain (= the synthetic token contract)
        // is connected to the correct token router contract on the origin chain (= the collateral contract)
        assertEq(routerForOrigin, encodedOriginTokenRouterAddress);

        bytes memory message = formatHyperlaneMessage({
            _version: 3,
            _nonce: 1,
            // `HypLSP7CollateralPausable` token router on ORIGIN_CHAIN_ID
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
