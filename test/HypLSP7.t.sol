// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.13;


import "forge-std/src/Test.sol";

import {TypeCasts} from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import {TestMailbox} from "@hyperlane-xyz/core/contracts/test/TestMailbox.sol";

import {LSP7Mock} from "./LSP7Mock.sol";
import {TestPostDispatchHook} from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";
import {TestInterchainGasPaymaster} from "@hyperlane-xyz/core/contracts/test/TestInterchainGasPaymaster.sol";
import {GasRouter} from "@hyperlane-xyz/core/contracts/client/GasRouter.sol";

import {HypLSP7} from "../src/HypLSP7.sol";
import {HypLSP7Collateral} from "../src/HypLSP7Collateral.sol";
import {HypNative} from "@hyperlane-xyz/core/contracts/token/HypNative.sol";
import {TokenRouter} from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";

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
    address internal  ALICE = makeAddr("alice");
    address internal  BOB = makeAddr("bob");
    address internal  OWNER = makeAddr("owner");

    LSP7Mock internal primaryToken;
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

        primaryToken = new LSP7Mock(NAME, SYMBOL, address(this), TOTAL_SUPPLY);

        noopHook = new TestPostDispatchHook();
        localMailbox.setDefaultHook(address(noopHook));
        localMailbox.setRequiredHook(address(noopHook));

        REQUIRED_VALUE = noopHook.quoteDispatch("", "");

        remoteToken = new HypLSP7(DECIMALS, address(remoteMailbox));

        // todo: add owner
        remoteToken.initialize(
            TOTAL_SUPPLY,
            NAME,
            SYMBOL,
            address(noopHook),
            address(0),
            OWNER
        );

        // call as owner
        vm.prank(OWNER);
        remoteToken.enrollRemoteRouter(ORIGIN, address(localToken).addressToBytes32());

        igp = new TestInterchainGasPaymaster();

        vm.deal(ALICE, 125000);
    }

    function _enrollRemoteTokenRouter() internal {
        vm.prank(OWNER);
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

        vm.prank(OWNER);
        localToken.setHook(address(igp));

        TokenRouter.GasRouterConfig[]
            memory config = new TokenRouter.GasRouterConfig[](1);
        config[0] = GasRouter.GasRouterConfig({
            domain: DESTINATION,
            gas: GAS_LIMIT
        });

        vm.prank(OWNER);
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

    }
}

contract HypLSP7Test is HypTokenTest {
    using TypeCasts for address;
    HypLSP7 internal lsp7Token;

    address internal owner = makeAddr("owner");

    function setUp() public override {
        super.setUp();

        localToken = new HypLSP7(DECIMALS, address(localMailbox));
        lsp7Token = HypLSP7(payable(address(localToken)));


        vm.prank(owner);
        lsp7Token.initialize(
            TOTAL_SUPPLY,
            NAME,
            SYMBOL,
            address(noopHook),
            address(0),
            owner
        );


        vm.prank(owner);
        lsp7Token.enrollRemoteRouter(
            DESTINATION,
            address(remoteToken).addressToBytes32()
        );


        // from, to, amount, force, data
        vm.prank(owner);

        lsp7Token.transfer(owner, ALICE, 1000e18, true, "");


        _enrollRemoteTokenRouter();
    }

    function testInitialize_revert_ifAlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        lsp7Token.initialize(
            TOTAL_SUPPLY,
            NAME,
            SYMBOL,
            address(noopHook),
            address(0),
            owner
        );
    }

    function testTotalSupply() public {
        assertEq(lsp7Token.totalSupply(), TOTAL_SUPPLY);
    }

    function testDecimals() public {
        assertEq(lsp7Token.decimals(), DECIMALS);
    }

    function testLocalTransfers() public {
        assertEq(lsp7Token.balanceOf(ALICE), 1000e18);
        assertEq(lsp7Token.balanceOf(BOB), 0);

        vm.prank(ALICE);
        lsp7Token.transfer(ALICE, BOB, 100e18, true, "");
        assertEq(lsp7Token.balanceOf(ALICE), 900e18);
        assertEq(lsp7Token.balanceOf(BOB), 100e18);
    }

    function testRemoteTransfer() public {
        vm.prank(owner);
        remoteToken.enrollRemoteRouter(
            ORIGIN,
            address(localToken).addressToBytes32()
        );
        uint256 balanceBefore = lsp7Token.balanceOf(ALICE);

        _performRemoteTransferWithEmit(REQUIRED_VALUE, TRANSFER_AMT, 0);
        assertEq(lsp7Token.balanceOf(ALICE), balanceBefore - TRANSFER_AMT);
    }

    function testRemoteTransfer_invalidAmount() public {
        vm.expectRevert();
        _performRemoteTransfer(REQUIRED_VALUE, TRANSFER_AMT * 11);
        assertEq(lsp7Token.balanceOf(ALICE), 1000e18);
    }

    function testRemoteTransfer_withCustomGasConfig() public {
        _setCustomGasConfig();

        uint256 balanceBefore = lsp7Token.balanceOf(ALICE);

        _performRemoteTransferAndGas(
            REQUIRED_VALUE,
            TRANSFER_AMT,
            GAS_LIMIT * igp.gasPrice()
        );

        assertEq(lsp7Token.balanceOf(ALICE), balanceBefore - TRANSFER_AMT);
    }
}

contract HypLSP7CollateralTest is HypTokenTest {
    using TypeCasts for address;
    HypLSP7Collateral internal lsp7Collateral;

    address internal owner = makeAddr("owner");

    function setUp() public override {
        super.setUp();

        localToken = new HypLSP7Collateral(
            address(primaryToken),
            address(localMailbox)
        );


        lsp7Collateral = HypLSP7Collateral(address(localToken));

        lsp7Collateral.initialize(
            address(noopHook),
            address(0),
            OWNER
        );

        vm.prank(owner);
        lsp7Collateral.enrollRemoteRouter(
            DESTINATION,
            address(remoteToken).addressToBytes32()
        );

        primaryToken.transfer(address(this), address(localToken), 1000e18, true, "");

        primaryToken.transfer(address(this), ALICE, 1000e18, true, "");

        _enrollRemoteTokenRouter();
    }

    function testInitialize_revert_ifAlreadyInitialized() public {}

    function testRemoteTransfer() public {
        uint256 balanceBefore = localToken.balanceOf(ALICE);

        vm.prank(ALICE);
        primaryToken.authorizeOperator(address(localToken), TRANSFER_AMT, "");

        _performRemoteTransferWithEmit(REQUIRED_VALUE, TRANSFER_AMT, 0);
        assertEq(localToken.balanceOf(ALICE), balanceBefore - TRANSFER_AMT);
    }

    function testRemoteTransfer_invalidAllowance() public {
        vm.expectRevert();
        _performRemoteTransfer(REQUIRED_VALUE, TRANSFER_AMT);
        assertEq(localToken.balanceOf(ALICE), 1000e18);
    }

    function testRemoteTransfer_withCustomGasConfig() public {
        _setCustomGasConfig();

        uint256 balanceBefore = localToken.balanceOf(ALICE);


        vm.prank(ALICE);
        // primaryToken.authorizeOperator(address(localToken), TRANSFER_AMT, "");
        primaryToken.authorizeOperator(address(localToken), TRANSFER_AMT, "");
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

    address internal owner = makeAddr("owner");

    function setUp() public override {
        super.setUp();

        localToken = new HypNative(address(localMailbox));
        nativeToken = HypNative(payable(address(localToken)));

        nativeToken.initialize(
            address(noopHook),
            address(0),
            OWNER
        );

        vm.prank(owner);
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
