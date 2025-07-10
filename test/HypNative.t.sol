// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// test utilities
import { HypTokenTestOld } from "./helpers/HypTokenTestOld.sol";

// Mocks + contracts to test
import { HypNative } from "@hyperlane-xyz/core/contracts/token/HypNative.sol";

// Hyperlane testing environnement

// - Mock test contracts
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";

// - Hyperlane types and modules
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";

contract HypNativeTest is HypTokenTestOld {
    HypNative internal nativeToken;
    // parameter used for native tokens that use different number of decimals than 1e18
    uint256 constant SCALE_NATIVE = 1;

    function setUp() public override {
        super.setUp();

        localToken = new HypNative(SCALE_NATIVE, address(localMailbox));
        nativeToken = HypNative(payable(address(localToken)));

        nativeToken.initialize(address(noopHook), address(0), WARP_ROUTE_OWNER);

        vm.prank(WARP_ROUTE_OWNER);
        nativeToken.enrollRemoteRouter(DESTINATION, TypeCasts.addressToBytes32(address(remoteToken)));

        vm.deal(address(localToken), 1000e18);
        vm.deal(ALICE, 1000e18);

        _enrollRemoteTokenRouter();
    }

    function testTransfer_withHookSpecified(uint256 fee, bytes calldata metadata) public override {
        TestPostDispatchHook hook = new TestPostDispatchHook();
        hook.setFee(fee);

        uint256 value = REQUIRED_INTERCHAIN_GAS_PAYMENT + TRANSFER_AMOUNT;

        vm.prank(ALICE);
        primaryToken.authorizeOperator(address(localToken), TRANSFER_AMOUNT, "");
        bytes32 messageId = _performRemoteTransferWithHook(value, TRANSFER_AMOUNT, address(hook), metadata);
        assertTrue(hook.messageDispatched(messageId));
    }

    function testRemoteTransfer() public {
        _performRemoteTransferWithEmit(REQUIRED_INTERCHAIN_GAS_PAYMENT, TRANSFER_AMOUNT, TRANSFER_AMOUNT);
    }

    function testRemoteTransfer_invalidAmount() public {
        vm.expectRevert("Native: amount exceeds msg.value");
        _performRemoteTransfer(REQUIRED_INTERCHAIN_GAS_PAYMENT + TRANSFER_AMOUNT, TRANSFER_AMOUNT * 10);
        assertEq(localToken.balanceOf(ALICE), 1000e18);
    }

    function testRemoteTransfer_withCustomGasConfig() public {
        _setCustomGasConfig();

        _performRemoteTransferAndGas(
            REQUIRED_INTERCHAIN_GAS_PAYMENT,
            TRANSFER_AMOUNT,
            TRANSFER_AMOUNT + GAS_LIMIT * interchainGasPaymaster.gasPrice()
        );
    }

    function test_transferRemote_reverts_whenAmountExceedsValue(uint256 nativeValue) public {
        vm.assume(nativeValue < address(this).balance);

        address recipient = address(0xdeadbeef);
        bytes32 encodedRecipient = TypeCasts.addressToBytes32(recipient);
        vm.expectRevert("Native: amount exceeds msg.value");
        nativeToken.transferRemote{ value: nativeValue }(DESTINATION, encodedRecipient, nativeValue + 1);

        vm.expectRevert("Native: amount exceeds msg.value");
        nativeToken.transferRemote{ value: nativeValue }(
            DESTINATION, encodedRecipient, nativeValue + 1, bytes(""), address(0)
        );
    }
}
