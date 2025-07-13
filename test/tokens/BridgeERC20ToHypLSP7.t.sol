// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { console } from "forge-std/src/console.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// mocks
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";
import { TestIsm } from "@hyperlane-xyz/core/contracts/test/TestIsm.sol";
import { CustomPostDispatchHook } from "../helpers/CustomPostDispatchHook.sol";
import { ERC20Mock } from "../helpers/ERC20Mock.sol";

import { HypTokenTest } from "../helpers/HypTokenTest.sol";
import { HypERC20Collateral } from "@hyperlane-xyz/core/contracts/token/HypERC20Collateral.sol";
import { HypLSP7 } from "../../src/HypLSP7.sol";

import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";

// errors
import { LSP7AmountExceedsBalance } from "@lukso/lsp7-contracts/contracts/LSP7Errors.sol";

/**
 * @title Bridge token routes tests from ERC20 to HypLSP7
 *
 * @dev Hyperlane warp route tests.
 *  - origin chain: ERC20 tokens locked in `HypERC20Collateral`
 *  - destination chain: synthetic tokens minted as `HypLSP7`
 */
contract BridgeERC20ToHypLSP7 is HypTokenTest {
    // Token being bridged
    // In production, we assume it is an ERC20 token already deployed
    // (on Ethereum or any other EVM origin chain)
    // ---------------------------
    string internal constant NAME = "Test USDC";
    string internal constant SYMBOL = "tUSDC";
    uint8 internal constant DECIMALS = 6; // USDC has 6 decimals points
    uint256 internal constant TOTAL_SUPPLY = 1_000_000 * (10 ** DECIMALS);

    ERC20Mock internal token;

    // Warp route
    // ---------------------------
    HypERC20Collateral internal erc20Collateral;
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

        // Setup Hyperlane Mailboxes
        super.setUp();

        // 1. Deploy the initial token that we will bridge from the origin chain
        token = new ERC20Mock(NAME, SYMBOL, TOTAL_SUPPLY, DECIMALS);
        token.transfer(ALICE, 100_000 * (10 ** DECIMALS));

        // 2. Deploy collateral token router
        originDefaultHook = new TestPostDispatchHook();
        originDefaultIsm = new TestIsm();

        erc20Collateral = new HypERC20Collateral(address(token), SCALE_PARAM, address(originMailbox));
        erc20Collateral.initialize(address(originDefaultHook), address(originDefaultIsm), WARP_ROUTE_OWNER);

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
        originTokenRouter = erc20Collateral;
        destinationTokenRouter = syntheticToken;

        // 5. Connect the collateral with the synthetic contract, and vice versa
        vm.prank(WARP_ROUTE_OWNER);
        HypTokenTest._enrollOriginTokenRouter();

        vm.prank(WARP_ROUTE_OWNER);
        HypTokenTest._enrollDestinationTokenRouter();
    }

    function test_constructorRevertIfInvalidToken() public {
        vm.expectRevert("HypERC20Collateral: invalid token");
        new HypERC20Collateral(address(0), SCALE_PARAM, address(originMailbox));
    }

    // ==========================
    // |     Test Bridge Tx     |
    // |  Origin -> Destination |
    // ==========================

    function test_BridgeTx() public {
        uint256 balanceBefore = token.balanceOf(ALICE);

        vm.prank(ALICE);
        token.approve(address(erc20Collateral), TRANSFER_AMOUNT);

        _performBridgeTxAndCheckSentTransferRemoteEvent(REQUIRED_INTERCHAIN_GAS_PAYMENT, TRANSFER_AMOUNT);
        assertEq(token.balanceOf(ALICE), balanceBefore - TRANSFER_AMOUNT);

        // CHECK tokens have been locked in the collateral contract on origin chain
        assertEq(token.balanceOf(address(erc20Collateral)), TRANSFER_AMOUNT);

        // CHECK synthetic tokens have been minted for Bob on destination chain
        assertEq(syntheticToken.balanceOf(BOB), TRANSFER_AMOUNT);
    }

    function test_BridgeTxWithHookSpecified(uint256 fee, bytes calldata metadata) public virtual {
        CustomPostDispatchHook customHook = new CustomPostDispatchHook();
        customHook.setFee(fee);

        vm.prank(ALICE);
        token.approve(address(erc20Collateral), TRANSFER_AMOUNT);

        vm.expectEmit({ emitter: address(customHook) });
        emit CustomPostDispatchHook.CustomPostDispatchHookCalled(metadata);

        bytes32 messageId = _performBridgeTxWithHookSpecified(
            REQUIRED_INTERCHAIN_GAS_PAYMENT, TRANSFER_AMOUNT, address(customHook), metadata
        );

        assertTrue(customHook.messageDispatched(messageId));
        assertEq(syntheticToken.balanceOf(BOB), TRANSFER_AMOUNT);
    }

    function test_TotalSupplyOfSyntheticTokenIncreasesAfterBridgeTx(uint256 transferAmount) public {
        uint256 syntheticTokenSupplyBefore = syntheticToken.totalSupply();

        uint256 maxERC20TokenAmount = token.totalSupply();

        // move all the tokens to Alice to ensure fuzzer can test up to the total supply being transferred
        token.transfer(ALICE, token.balanceOf(address(this)));
        assertEq(token.balanceOf(ALICE), maxERC20TokenAmount);

        transferAmount = bound(transferAmount, 1, maxERC20TokenAmount);

        vm.prank(ALICE);
        token.approve(address(erc20Collateral), transferAmount);

        _performBridgeTx(0, transferAmount);

        assertEq(syntheticToken.totalSupply(), syntheticTokenSupplyBefore + transferAmount);
    }

    function test_BridgeTxRevertsIfAmountGreaterThanUserERC20TokenBalance(uint256 transferAmount) public {
        uint256 aliceBalance = token.balanceOf(ALICE);
        vm.assume(aliceBalance > 0);

        transferAmount = bound(transferAmount, aliceBalance + 1, token.totalSupply());

        vm.prank(ALICE);
        token.approve(address(erc20Collateral), transferAmount);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(ALICE);
        erc20Collateral.transferRemote{ value: REQUIRED_INTERCHAIN_GAS_PAYMENT }(
            DESTINATION_CHAIN_ID, TypeCasts.addressToBytes32(BOB), transferAmount
        );
    }

    function test_BridgeTxRevertsIfNoAllowanceGivenToCollateral(uint256 transferAmount) public {
        vm.assume(transferAmount != 0);
        uint256 aliceBalance = token.balanceOf(ALICE);

        vm.expectRevert("ERC20: insufficient allowance");
        vm.prank(ALICE);
        erc20Collateral.transferRemote{ value: REQUIRED_INTERCHAIN_GAS_PAYMENT }(
            DESTINATION_CHAIN_ID, TypeCasts.addressToBytes32(BOB), transferAmount
        );

        // CHECK the balances did not change
        assertEq(token.balanceOf(ALICE), aliceBalance);
        assertEq(syntheticToken.balanceOf(BOB), 0);
    }

    /// forge-config: default.fuzz.max_test_rejects = 1_000_000
    function test_BridgeTxRevertsIfTransferAmountIsMoreThanAllowance(
        uint256 approvedAmount,
        uint256 invalidTransferAmount
    )
        public
    {
        uint256 aliceBalance = token.balanceOf(ALICE);
        vm.assume(aliceBalance > 0);

        approvedAmount = bound(approvedAmount, 1, aliceBalance); // valid approved amount
        vm.assume(invalidTransferAmount > approvedAmount);

        // Alice approve the collateral contract for X amount
        vm.prank(ALICE);
        token.approve(address(erc20Collateral), approvedAmount);

        // Alice to try to do transferRemote with Y amount, where Y > X
        vm.expectRevert("ERC20: insufficient allowance");
        vm.prank(ALICE);
        erc20Collateral.transferRemote{ value: REQUIRED_INTERCHAIN_GAS_PAYMENT }(
            DESTINATION_CHAIN_ID, TypeCasts.addressToBytes32(BOB), invalidTransferAmount
        );

        // CHECK the balances did not change
        assertEq(token.balanceOf(ALICE), aliceBalance);
        assertEq(syntheticToken.balanceOf(BOB), 0);
    }

    function test_BridgeTxWithCustomGasConfig() public {
        _setCustomGasConfig(erc20Collateral);
        uint256 gasOverhead = GAS_LIMIT * interchainGasPaymaster.gasPrice();

        vm.prank(ALICE);
        token.approve(address(erc20Collateral), TRANSFER_AMOUNT);

        uint256 tokenBalanceBefore = token.balanceOf(ALICE);
        uint256 ethBalanceBefore = ALICE.balance;

        _performBridgeTxWithCustomGasConfig({
            _msgValue: REQUIRED_INTERCHAIN_GAS_PAYMENT,
            _amount: TRANSFER_AMOUNT,
            _gasOverhead: GAS_LIMIT * interchainGasPaymaster.gasPrice()
        });
        assertEq(token.balanceOf(ALICE), tokenBalanceBefore - TRANSFER_AMOUNT);

        uint256 expectedNewETHBalance = ethBalanceBefore - REQUIRED_INTERCHAIN_GAS_PAYMENT - gasOverhead;
        assertEq(ALICE.balance, expectedNewETHBalance);
    }

    /// @dev Ensure correct behaviour of `syntheticToken.transfer(from, to, amount, force, data)`
    function test_CanTransferSyntheticTokensBetweenAddressesOnDestinationChain() public {
        uint256 aliceTokenBalanceBefore = token.balanceOf(ALICE);
        uint256 bobSyntheticTokenBalanceBefore = syntheticToken.balanceOf(BOB);

        assertEq(bobSyntheticTokenBalanceBefore, 0);

        vm.prank(ALICE);
        token.approve(address(erc20Collateral), TRANSFER_AMOUNT);

        // Bridge tokens to BOB on destination chain
        _performBridgeTxAndCheckSentTransferRemoteEvent(REQUIRED_INTERCHAIN_GAS_PAYMENT, TRANSFER_AMOUNT);
        assertEq(token.balanceOf(ALICE), aliceTokenBalanceBefore - TRANSFER_AMOUNT);

        // CHECK that BOB can transfer synthetic tokens on destination chain
        address recipient = makeAddr("recipient");
        uint256 amount = 20 * (10 ** DECIMALS);

        uint256 bobSyntheticTokenBalanceAfter = syntheticToken.balanceOf(BOB);
        assertEq(bobSyntheticTokenBalanceAfter, bobSyntheticTokenBalanceBefore + TRANSFER_AMOUNT);
        assertEq(syntheticToken.balanceOf(recipient), 0);

        vm.prank(BOB);
        syntheticToken.transfer(BOB, recipient, amount, true, "");

        assertEq(syntheticToken.balanceOf(BOB), bobSyntheticTokenBalanceAfter - amount);
        assertEq(syntheticToken.balanceOf(recipient), amount);
    }

    // ==============================
    // |     Test Bridging Back     |
    // |    Origin <- Destination   |
    // ==============================

    function test_BridgeBackTxRevertsIfAmountGreaterThanUserSyntheticTokenBalance(
        uint256 syntheticTokenBalance,
        uint256 transferAmount
    )
        public
    {
        vm.assume(syntheticTokenBalance <= TOTAL_SUPPLY);
        vm.assume(syntheticTokenBalance < transferAmount);

        // we assume some tokens have already been bridged on the destination chain
        _processBridgeTxOnDestinationChain(BOB, syntheticTokenBalance);

        assertEq(syntheticToken.balanceOf(BOB), syntheticTokenBalance);

        vm.expectRevert(
            abi.encodeWithSelector(LSP7AmountExceedsBalance.selector, syntheticTokenBalance, BOB, transferAmount)
        );
        vm.prank(BOB);
        syntheticToken.transferRemote{ value: REQUIRED_INTERCHAIN_GAS_PAYMENT }(
            ORIGIN_CHAIN_ID, TypeCasts.addressToBytes32(ALICE), transferAmount
        );
    }

    function test_BenchmarkOverheadGasUsageWhenBridgingBack() public {
        // to transfer from the collateral contract, we assume some tokens have already been locked in there
        token.transfer(address(erc20Collateral), TRANSFER_AMOUNT);

        vm.prank(address(originMailbox));

        uint256 gasBefore = gasleft();
        erc20Collateral.handle(
            DESTINATION_CHAIN_ID,
            TypeCasts.addressToBytes32(address(syntheticToken)),
            abi.encodePacked(TypeCasts.addressToBytes32(BOB), TRANSFER_AMOUNT)
        );
        uint256 gasAfter = gasleft();

        console.log("BridgeERC20ToHypLSP7 - Overhead gas usage when bridging back: %d", gasBefore - gasAfter);
    }
}
