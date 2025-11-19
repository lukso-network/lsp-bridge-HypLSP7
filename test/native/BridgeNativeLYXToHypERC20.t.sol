// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

// test utilities
import { HypTokenTest } from "../helpers/HypTokenTest.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// Mock contracts
import { TestMailbox } from "@hyperlane-xyz/core/contracts/test/TestMailbox.sol";
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";
import { TestIsm } from "@hyperlane-xyz/core/contracts/test/TestIsm.sol";
import { CustomPostDispatchHook } from "../helpers/CustomPostDispatchHook.sol";

// contracts to test
import { HypNative } from "@hyperlane-xyz/core/contracts/token/HypNative.sol";
import { HypERC20 } from "@hyperlane-xyz/core/contracts/token/HypERC20.sol";
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";

// libraries
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";

/**
 * @title Bridge token routes tests from native tokens to `HypERC20`
 *
 * @dev Hyperlane warp route tests.
 *  - origin chain: native tokens (LYX) locked in `HypNative`
 *  - destination chain: synthetic tokens minted as `HypERC20`
 */
contract BridgeNativeLYXToHypERC20 is HypTokenTest {
    // Native tokens being bridged
    uint8 internal constant DECIMALS = 18;
    uint256 internal constant USER_BALANCE = 1_000_000 * (10 ** DECIMALS);

    // Name given to the synthetic token on the destination chain
    string internal constant NAME = "LYX (bridged from LUKSO)";
    string internal constant SYMBOL = "LYX";

    // Warp route
    // ---------------------------
    HypNative internal nativeCollateral;
    TestPostDispatchHook internal originDefaultHook;
    TestIsm internal originDefaultIsm;

    HypERC20 internal syntheticToken;
    TestPostDispatchHook internal destinationDefaultHook;
    TestIsm internal destinationDefaultIsm;

    // Scale outbount amounts down and inbound amounts up.
    // Used when different chains of the route have different decimals place to unify semantics of amounts in message.
    // Since we are bridging between two similar EVM chains, scaling is not required so we keep the parameter to 1.
    uint256 internal constant SCALE_PARAM = 1;

    address internal immutable PROXY_ADMIN = makeAddr("Proxy Admin");

    // constants for testing
    // ---------------------------
    uint256 internal constant TRANSFER_AMOUNT = 100 * (10 ** DECIMALS);

    function setUp() public virtual override {
        ORIGIN_CHAIN_ID = 42; // LUKSO
        DESTINATION_CHAIN_ID = 1; // Ethereum

        REQUIRED_INTERCHAIN_GAS_PAYMENT = 10_000 gwei;

        // Setup Hyperlane Mailboxes
        super.setUp();

        /// 1. Give some native tokens to Alice to allow her to bridge
        vm.deal(ALICE, USER_BALANCE);

        // 2. Deploy collateral token router
        originDefaultHook = new TestPostDispatchHook();
        originDefaultIsm = new TestIsm();

        nativeCollateral = new HypNative(SCALE_PARAM, address(originMailbox));
        nativeCollateral.initialize(address(originDefaultHook), address(originDefaultIsm), WARP_ROUTE_OWNER);

        // 3. Deploy the synthetic token on the destination chain + initialize it
        destinationDefaultHook = new TestPostDispatchHook();
        destinationDefaultIsm = new TestIsm();

        HypERC20 implementation = new HypERC20(DECIMALS, SCALE_PARAM, address(destinationMailbox));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            PROXY_ADMIN,
            abi.encodeCall(
                HypERC20.initialize,
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

        syntheticToken = HypERC20(address(proxy));

        // 4. setup the state variable derives from `HypTokenTest` to ensure
        // the internal helper functions can be used
        originTokenRouter = nativeCollateral;
        destinationTokenRouter = syntheticToken;

        // 5. Connect the collateral with the synthetic contract, and vice versa
        vm.prank(WARP_ROUTE_OWNER);
        HypTokenTest._connectOriginTokenRouter();

        vm.prank(WARP_ROUTE_OWNER);
        HypTokenTest._connectDestinationTokenRouter();
    }

    function test_BridgeTx() public {
        uint256 balanceBefore = ALICE.balance;

        _performBridgeTxAndCheckSentTransferRemoteEvent({
            _msgValue: TRANSFER_AMOUNT + REQUIRED_INTERCHAIN_GAS_PAYMENT,
            _amount: TRANSFER_AMOUNT
        });
        assertEq(ALICE.balance, balanceBefore - TRANSFER_AMOUNT - REQUIRED_INTERCHAIN_GAS_PAYMENT);

        // CHECK tokens have been locked in the collateral contract
        assertEq(address(nativeCollateral).balance, TRANSFER_AMOUNT);
    }

    function test_BridgeTxWithHookSpecified(uint256 fee, bytes calldata metadata) public virtual {
        CustomPostDispatchHook customHook = new CustomPostDispatchHook();
        customHook.setFee(fee);

        vm.expectEmit({ emitter: address(customHook) });
        emit CustomPostDispatchHook.CustomPostDispatchHookCalled(metadata);

        bytes32 messageId = _performBridgeTxWithHookSpecified({
            _msgValue: TRANSFER_AMOUNT + REQUIRED_INTERCHAIN_GAS_PAYMENT,
            _amount: TRANSFER_AMOUNT,
            _hook: address(customHook),
            _hookMetadata: metadata
        });
        assertTrue(customHook.messageDispatched(messageId));
        assertEq(syntheticToken.balanceOf(BOB), TRANSFER_AMOUNT);
    }

    function test_BridgeTxWithCustomGasConfig() public {
        _setCustomGasConfig(nativeCollateral);
        uint256 gasOverhead = GAS_LIMIT * interchainGasPaymaster.gasPrice();

        uint256 lyxBalanceBefore = ALICE.balance;

        _performBridgeTxWithCustomGasConfig({
            _msgValue: TRANSFER_AMOUNT + REQUIRED_INTERCHAIN_GAS_PAYMENT,
            _amount: TRANSFER_AMOUNT,
            _gasOverhead: gasOverhead
        });

        uint256 expectedNewLYXBalance =
            lyxBalanceBefore - TRANSFER_AMOUNT - REQUIRED_INTERCHAIN_GAS_PAYMENT - gasOverhead;
        assertEq(ALICE.balance, expectedNewLYXBalance);
    }

    function test_BridgeTxRevertsIfAmountGreaterThanUserNativeTokenBalance() public {
        uint256 invalidTransferAmount = TRANSFER_AMOUNT * 10;

        vm.expectRevert("Native: amount exceeds msg.value");
        vm.prank(ALICE);
        nativeCollateral.transferRemote{ value: TRANSFER_AMOUNT + REQUIRED_INTERCHAIN_GAS_PAYMENT }(
            DESTINATION_CHAIN_ID, TypeCasts.addressToBytes32(BOB), invalidTransferAmount
        );
    }

    function test_BridgeTxRevertsWhenAmountExceedsValue(uint256 nativeValue) public {
        vm.assume(nativeValue < address(this).balance);

        address recipient = address(0xdeadbeef);
        bytes32 encodedRecipient = TypeCasts.addressToBytes32(recipient);
        vm.expectRevert("Native: amount exceeds msg.value");
        nativeCollateral.transferRemote{ value: nativeValue }(DESTINATION_CHAIN_ID, encodedRecipient, nativeValue + 1);

        vm.expectRevert("Native: amount exceeds msg.value");
        nativeCollateral.transferRemote{ value: nativeValue }(
            DESTINATION_CHAIN_ID, encodedRecipient, nativeValue + 1, bytes(""), address(0)
        );
    }

    function test_ConnectToNewChainAndBridge() public {
        uint32 newChainId = 8453; // Base
        TestMailbox newChainMailbox = new TestMailbox({ _localDomain: newChainId });

        // Deploy a new HypERC20 synthetic token contract on the new chain
        TestPostDispatchHook newChainDefaultHook = new TestPostDispatchHook();
        TestIsm newChainDefaultIsm = new TestIsm();

        HypERC20 implementation = new HypERC20(DECIMALS, SCALE_PARAM, address(newChainMailbox));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            PROXY_ADMIN,
            abi.encodeCall(
                HypERC20.initialize,
                (
                    0, // initial supply (do not mint any synthetic tokens on initialization)
                    NAME,
                    SYMBOL,
                    address(newChainDefaultHook),
                    address(newChainDefaultIsm),
                    WARP_ROUTE_OWNER
                )
            )
        );

        HypERC20 newChainSyntheticToken = HypERC20(address(proxy));

        // CHECK no address is connected for this new chainId
        assertEq(nativeCollateral.routers(newChainId), bytes32(0));
        assertEq(newChainSyntheticToken.routers(ORIGIN_CHAIN_ID), bytes32(0));

        // CHECK we cannot bridge
        vm.prank(ALICE);
        vm.expectRevert("No router enrolled for domain: 8453");
        originTokenRouter.transferRemote{ value: TRANSFER_AMOUNT + REQUIRED_INTERCHAIN_GAS_PAYMENT }({
            _destination: newChainId,
            _recipient: TypeCasts.addressToBytes32(BOB),
            _amountOrId: TRANSFER_AMOUNT
        });

        // 1. Connect the origin router to the new chain
        vm.prank(WARP_ROUTE_OWNER);
        nativeCollateral.enrollRemoteRouter(newChainId, TypeCasts.addressToBytes32(address(newChainSyntheticToken)));

        vm.prank(WARP_ROUTE_OWNER);
        newChainSyntheticToken.enrollRemoteRouter(
            ORIGIN_CHAIN_ID, TypeCasts.addressToBytes32(address(nativeCollateral))
        );

        // CHECK collateral and synthetic contracts are now connected
        assertEq(nativeCollateral.routers(newChainId), TypeCasts.addressToBytes32(address(newChainSyntheticToken)));
        assertEq(newChainSyntheticToken.routers(ORIGIN_CHAIN_ID), TypeCasts.addressToBytes32(address(nativeCollateral)));

        // 2. Perform a bridge transaction to the new chain
        uint256 aliceNativeTokenBalanceBefore = ALICE.balance;
        assertEq(newChainSyntheticToken.totalSupply(), 0);
        assertEq(newChainSyntheticToken.balanceOf(BOB), 0);

        // Test bridging to new chain

        // 2.1 Send the transfer remote transaction on the origin chain
        vm.prank(ALICE);
        vm.expectEmit({ emitter: address(nativeCollateral) }); // Check emitted event on source chain
        emit TokenRouter.SentTransferRemote(newChainId, TypeCasts.addressToBytes32(BOB), TRANSFER_AMOUNT);
        originTokenRouter.transferRemote{ value: TRANSFER_AMOUNT + REQUIRED_INTERCHAIN_GAS_PAYMENT }({
            _destination: newChainId,
            _recipient: TypeCasts.addressToBytes32(BOB),
            _amountOrId: TRANSFER_AMOUNT
        });

        // process the bridge transaction on the destination chain
        vm.prank(address(newChainMailbox));
        vm.expectEmit({ emitter: address(newChainSyntheticToken) });
        emit TokenRouter.ReceivedTransferRemote(ORIGIN_CHAIN_ID, TypeCasts.addressToBytes32(BOB), TRANSFER_AMOUNT);
        newChainSyntheticToken.handle(
            ORIGIN_CHAIN_ID,
            TypeCasts.addressToBytes32(address(nativeCollateral)),
            abi.encodePacked(TypeCasts.addressToBytes32(BOB), TRANSFER_AMOUNT)
        );

        // CHECK Alice's and Bob's balances have been updated
        assertEq(ALICE.balance, aliceNativeTokenBalanceBefore - TRANSFER_AMOUNT - REQUIRED_INTERCHAIN_GAS_PAYMENT);
        assertEq(newChainSyntheticToken.totalSupply(), TRANSFER_AMOUNT);
        assertEq(newChainSyntheticToken.balanceOf(BOB), TRANSFER_AMOUNT);
    }

    function test_TransferOwnership() public {
        address newOwner = makeAddr("new owner");

        assertEq(nativeCollateral.owner(), WARP_ROUTE_OWNER);
        assertEq(syntheticToken.owner(), WARP_ROUTE_OWNER);

        vm.prank(WARP_ROUTE_OWNER);
        nativeCollateral.transferOwnership(newOwner);
        assertEq(nativeCollateral.owner(), newOwner);

        vm.prank(WARP_ROUTE_OWNER);
        syntheticToken.transferOwnership(newOwner);
        assertEq(syntheticToken.owner(), newOwner);
    }
}
