// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";
import { TestIsm } from "@hyperlane-xyz/core/contracts/test/TestIsm.sol";
import { CustomPostDispatchHook } from "../helpers/CustomPostDispatchHook.sol";

import { HypTokenTest } from "../helpers/HypTokenTest.sol";
import { HypNative } from "@hyperlane-xyz/core/contracts/token/HypNative.sol";
import { HypLSP7 } from "../../contracts/HypLSP7.sol";

import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";

/**
 * @title Bridge token routes tests from native tokens to `HypLSP7`
 *
 * @dev Hyperlane warp route tests.
 *  - origin chain: native tokens (ETH) locked in `HypNative`
 *  - destination chain: synthetic tokens minted as `HypLSP7`
 */
contract BridgeNativeETHToHypLSP7 is HypTokenTest {
    // Native tokens being bridged
    uint8 internal constant DECIMALS = 18;
    uint256 internal constant USER_BALANCE = 1_000_000 * (10 ** DECIMALS);

    // Name given to the synthetic token on the destination chain
    string internal constant NAME = "ETH (bridged from Ethereum)";
    string internal constant SYMBOL = "ETH";

    // Warp route
    // ---------------------------
    HypNative internal nativeCollateral;
    TestPostDispatchHook internal originDefaultHook;
    TestIsm internal originDefaultIsm;

    HypLSP7 internal syntheticToken;
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
        ORIGIN_CHAIN_ID = 1; // Ethereum
        DESTINATION_CHAIN_ID = 42; // LUKSO

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

        HypLSP7 implementation = new HypLSP7(DECIMALS, SCALE_PARAM, address(destinationMailbox));
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

        syntheticToken = HypLSP7(payable(proxy));

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

        uint256 ethBalanceBefore = ALICE.balance;

        _performBridgeTxWithCustomGasConfig({
            _msgValue: TRANSFER_AMOUNT + REQUIRED_INTERCHAIN_GAS_PAYMENT,
            _amount: TRANSFER_AMOUNT,
            _gasOverhead: gasOverhead
        });

        uint256 expectedNewETHBalance =
            ethBalanceBefore - TRANSFER_AMOUNT - REQUIRED_INTERCHAIN_GAS_PAYMENT - gasOverhead;
        assertEq(ALICE.balance, expectedNewETHBalance);
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
}
