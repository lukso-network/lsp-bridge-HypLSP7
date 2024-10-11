// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.13;


import "forge-std/Test.sol";

import {TypeCasts} from "@hyperlane-xyz/core/libs/TypeCasts.sol";
import {TestMailbox} from "@hyperlane-xyz/core/test/TestMailbox.sol";
import {ERC20Test} from "@hyperlane-xyz/core/test/ERC20Test.sol";
import {TestPostDispatchHook} from "@hyperlane-xyz/core/test/TestPostDispatchHook.sol";
import {TestInterchainGasPaymaster} from "@hyperlane-xyz/core/test/TestInterchainGasPaymaster.sol";
import {GasRouter} from "@hyperlane-xyz/core/client/GasRouter.sol";

import {HypLSP7} from "../src/HypLSP7.sol";
import {HypERC20Collateral} from "@hyperlane-xyz/core/token/HypERC20Collateral.sol";
import {HypNative} from "@hyperlane-xyz/core/token/HypNative.sol";
import {TokenRouter} from "@hyperlane-xyz/core/token/libs/TokenRouter.sol";

abstract contract HypTokenTest is Test {
    using TypeCasts for address;
    uint32 internal constant ORIGIN = 11;
    uint32 internal constant DESTINATION = 12;
    uint8 internal constant DECIMALS = 18;
    uint256 internal constant TOTAL_SUPPLY = 1_000_000e18;
    uint256 internal REQUIRED_VALUE; // initialized in setUp
    uint256 internal constant GAS_LIMIT = 10_000;
    uint256 internal constant TRANSFER_AMT = 100e18;
    string internal constant NAME = "HyperlaneInu";
    string internal constant SYMBOL = "HYP";
    address internal constant ALICE = address(0x1);
    address internal constant BOB = address(0x2);

    ERC20Test internal primaryToken;
    TokenRouter internal localToken;
    HypLSP7 internal remoteToken;
    TestMailbox internal localMailbox;
    TestMailbox internal remoteMailbox;
    TestPostDispatchHook internal noopHook;
    TestInterchainGasPaymaster internal igp;

    event SentTransferRemote(
        uint32 indexed destination,
        bytes32 indexed recipient,
        uint256 amount
    );

    event ReceivedTransferRemote(
        uint32 indexed origin,
        bytes32 indexed recipient,
        uint256 amount
    );

    function setUp() public virtual {
        localMailbox = new TestMailbox(ORIGIN);
        remoteMailbox = new TestMailbox(DESTINATION);

        primaryToken = new ERC20Test(NAME, SYMBOL, TOTAL_SUPPLY, DECIMALS);

        noopHook = new TestPostDispatchHook();
        localMailbox.setDefaultHook(address(noopHook));
        localMailbox.setRequiredHook(address(noopHook));

        REQUIRED_VALUE = noopHook.quoteDispatch("", "");

        remoteToken = new HypLSP7(DECIMALS, address(remoteMailbox));
        remoteToken.initialize(TOTAL_SUPPLY, NAME, SYMBOL);
        remoteToken.enrollRemoteRouter(
            ORIGIN,
            address(localToken).addressToBytes32()
        );
        igp = new TestInterchainGasPaymaster();
        vm.deal(ALICE, 125000);
    }

    function _enrollRemoteTokenRouter() internal {
        remoteToken.enrollRemoteRouter(
            ORIGIN,
            address(localToken).addressToBytes32()
        );
    }

    function _expectRemoteBalance(address _user, uint256 _balance) internal {
        assertEq(remoteToken.balanceOf(_user), _balance);
    }

    function _processTransfers(address _recipient, uint256 _amount) internal {
        vm.prank(address(remoteMailbox));
        remoteToken.handle(
            ORIGIN,
            address(localToken).addressToBytes32(),
            abi.encodePacked(_recipient.addressToBytes32(), _amount)
        );
    }

    function _setCustomGasConfig() internal {
        localToken.setHook(address(igp));

        TokenRouter.GasRouterConfig[]
            memory config = new TokenRouter.GasRouterConfig[](1);
        config[0] = GasRouter.GasRouterConfig({
            domain: DESTINATION,
            gas: GAS_LIMIT
        });
        localToken.setDestinationGas(config);
    }

    function _performRemoteTransfer(
        uint256 _msgValue,
        uint256 _amount
    ) internal {
        vm.prank(ALICE);
        localToken.transferRemote{value: _msgValue}(
            DESTINATION,
            BOB.addressToBytes32(),
            _amount
        );

        vm.expectEmit(true, true, false, true);
        emit ReceivedTransferRemote(ORIGIN, BOB.addressToBytes32(), _amount);
        _processTransfers(BOB, _amount);

        assertEq(remoteToken.balanceOf(BOB), _amount);
    }

    function _performRemoteTransferAndGas(
        uint256 _msgValue,
        uint256 _amount,
        uint256 _gasOverhead
    ) internal {
        uint256 ethBalance = ALICE.balance;
        _performRemoteTransfer(_msgValue + _gasOverhead, _amount);
        assertEq(ALICE.balance, ethBalance - REQUIRED_VALUE - _gasOverhead);
    }

    function _performRemoteTransferWithEmit(
        uint256 _msgValue,
        uint256 _amount,
        uint256 _gasOverhead
    ) internal {
        vm.expectEmit(true, true, false, true);
        emit SentTransferRemote(DESTINATION, BOB.addressToBytes32(), _amount);
        _performRemoteTransferAndGas(_msgValue, _amount, _gasOverhead);
    }

    function testBenchmark_overheadGasUsage() public {
        vm.prank(address(localMailbox));

        uint256 gasBefore = gasleft();
        localToken.handle(
            DESTINATION,
            address(remoteToken).addressToBytes32(),
            abi.encodePacked(BOB.addressToBytes32(), TRANSFER_AMT)
        );
        uint256 gasAfter = gasleft();
        console.log("Overhead gas usage: %d", gasBefore - gasAfter);
    }
}

contract HypERC20Test is HypTokenTest {
    using TypeCasts for address;
    HypERC20 internal erc20Token;

    function setUp() public override {
        super.setUp();

        localToken = new HypERC20(DECIMALS, address(localMailbox));
        erc20Token = HypERC20(address(localToken));

        erc20Token.initialize(TOTAL_SUPPLY, NAME, SYMBOL);

        erc20Token.enrollRemoteRouter(
            DESTINATION,
            address(remoteToken).addressToBytes32()
        );
        erc20Token.transfer(ALICE, 1000e18);

        _enrollRemoteTokenRouter();
    }

    function testInitialize_revert_ifAlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        erc20Token.initialize(TOTAL_SUPPLY, NAME, SYMBOL);
    }

    function testTotalSupply() public {
        assertEq(erc20Token.totalSupply(), TOTAL_SUPPLY);
    }

    function testDecimals() public {
        assertEq(erc20Token.decimals(), DECIMALS);
    }

    function testLocalTransfers() public {
        assertEq(erc20Token.balanceOf(ALICE), 1000e18);
        assertEq(erc20Token.balanceOf(BOB), 0);

        vm.prank(ALICE);
        erc20Token.transfer(BOB, 100e18);
        assertEq(erc20Token.balanceOf(ALICE), 900e18);
        assertEq(erc20Token.balanceOf(BOB), 100e18);
    }

    function testRemoteTransfer() public {
        remoteToken.enrollRemoteRouter(
            ORIGIN,
            address(localToken).addressToBytes32()
        );
        uint256 balanceBefore = erc20Token.balanceOf(ALICE);
        _performRemoteTransferWithEmit(REQUIRED_VALUE, TRANSFER_AMT, 0);
        assertEq(erc20Token.balanceOf(ALICE), balanceBefore - TRANSFER_AMT);
    }

    function testRemoteTransfer_invalidAmount() public {
        vm.expectRevert("ERC20: burn amount exceeds balance");
        _performRemoteTransfer(REQUIRED_VALUE, TRANSFER_AMT * 11);
        assertEq(erc20Token.balanceOf(ALICE), 1000e18);
    }

    function testRemoteTransfer_withCustomGasConfig() public {
        _setCustomGasConfig();

        uint256 balanceBefore = erc20Token.balanceOf(ALICE);
        _performRemoteTransferAndGas(
            REQUIRED_VALUE,
            TRANSFER_AMT,
            GAS_LIMIT * igp.gasPrice()
        );
        assertEq(erc20Token.balanceOf(ALICE), balanceBefore - TRANSFER_AMT);
    }
}

contract HypERC20CollateralTest is HypTokenTest {
    using TypeCasts for address;
    HypERC20Collateral internal erc20Collateral;

    function setUp() public override {
        super.setUp();

        localToken = new HypERC20Collateral(
            address(primaryToken),
            address(localMailbox)
        );
        erc20Collateral = HypERC20Collateral(address(localToken));

        erc20Collateral.enrollRemoteRouter(
            DESTINATION,
            address(remoteToken).addressToBytes32()
        );

        primaryToken.transfer(address(localToken), 1000e18);
        primaryToken.transfer(ALICE, 1000e18);

        _enrollRemoteTokenRouter();
    }

    function testInitialize_revert_ifAlreadyInitialized() public {}

    function testRemoteTransfer() public {
        uint256 balanceBefore = localToken.balanceOf(ALICE);

        vm.prank(ALICE);
        primaryToken.approve(address(localToken), TRANSFER_AMT);
        _performRemoteTransferWithEmit(REQUIRED_VALUE, TRANSFER_AMT, 0);
        assertEq(localToken.balanceOf(ALICE), balanceBefore - TRANSFER_AMT);
    }

    function testRemoteTransfer_invalidAllowance() public {
        vm.expectRevert("ERC20: insufficient allowance");
        _performRemoteTransfer(REQUIRED_VALUE, TRANSFER_AMT);
        assertEq(localToken.balanceOf(ALICE), 1000e18);
    }

    function testRemoteTransfer_withCustomGasConfig() public {
        _setCustomGasConfig();

        uint256 balanceBefore = localToken.balanceOf(ALICE);

        vm.prank(ALICE);
        primaryToken.approve(address(localToken), TRANSFER_AMT);
        _performRemoteTransferAndGas(
            REQUIRED_VALUE,
            TRANSFER_AMT,
            GAS_LIMIT * igp.gasPrice()
        );
        assertEq(localToken.balanceOf(ALICE), balanceBefore - TRANSFER_AMT);
    }
}

contract HypNativeTest is HypTokenTest {
    using TypeCasts for address;
    HypNative internal nativeToken;

    function setUp() public override {
        super.setUp();

        localToken = new HypNative(address(localMailbox));
        nativeToken = HypNative(payable(address(localToken)));

        nativeToken.enrollRemoteRouter(
            DESTINATION,
            address(remoteToken).addressToBytes32()
        );

        vm.deal(address(localToken), 1000e18);
        vm.deal(ALICE, 1000e18);

        _enrollRemoteTokenRouter();
    }

    function testInitialize_revert_ifAlreadyInitialized() public {}

    function testRemoteTransfer() public {
        _performRemoteTransferWithEmit(
            REQUIRED_VALUE,
            TRANSFER_AMT,
            TRANSFER_AMT
        );
    }

    function testRemoteTransfer_invalidAmount() public {
        vm.expectRevert("Native: amount exceeds msg.value");
        _performRemoteTransfer(
            REQUIRED_VALUE + TRANSFER_AMT,
            TRANSFER_AMT * 10
        );
        assertEq(localToken.balanceOf(ALICE), 1000e18);
    }

    function testRemoteTransfer_withCustomGasConfig() public {
        _setCustomGasConfig();

        _performRemoteTransferAndGas(
            REQUIRED_VALUE,
            TRANSFER_AMT,
            TRANSFER_AMT + GAS_LIMIT * igp.gasPrice()
        );
    }
}
