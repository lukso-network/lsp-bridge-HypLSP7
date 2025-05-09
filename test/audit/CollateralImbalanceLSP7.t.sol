pragma solidity ^0.8.13;

// test utilities
import { Test } from "forge-std/src/Test.sol";
// import { Vm } from "forge-std/src/Vm.sol";
import { console } from "forge-std/src/console.sol";

/// Hyperlane testing environnement
/// @dev See https://docs.hyperlane.xyz/docs/guides/developer-tips/unit-testing
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import { TestMailbox } from "@hyperlane-xyz/core/contracts/test/TestMailbox.sol";
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";

// libraries
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";
import { TokenMessage } from "@hyperlane-xyz/core/contracts/token/libs/TokenMessage.sol";

// Mocks + contracts to test
import { LSP7Mock } from "../Mocks/LSP7Mock.sol";
import { HypLSP7 } from "../../src/HypLSP7.sol";
import { HypLSP7Collateral } from "../../src/HypLSP7Collateral.sol";

contract CollateralImbalanceLSP7 is Test {
    using TypeCasts for address;
    using TokenMessage for bytes;

    error InvalidRecipientError();

    address internal ATTACKER = makeAddr("attacker");
    address internal OWNER = makeAddr("owner");

    LSP7Mock internal lsp7;
    HypLSP7Collateral internal collateralToken;
    HypLSP7 internal syntheticToken;

    TestMailbox internal localMailbox;
    TestMailbox internal remoteMailbox;
    TestPostDispatchHook internal noopHook;

    uint32 internal constant ORIGIN = 11;
    uint32 internal constant DESTINATION = 12;
    uint8 internal constant DECIMALS = 18;
    uint256 internal constant TOTAL_SUPPLY = 1_000_000e18;
    uint256 internal constant GAS_LIMIT = 10_000;
    uint256 internal constant TRANSFER_AMOUNT = 100e18;
    string internal constant NAME = "HyperlaneInu";
    string internal constant SYMBOL = "HYP";

    uint256 internal amount = TRANSFER_AMOUNT;

    function setUp() public {
        localMailbox = new TestMailbox(ORIGIN);
        remoteMailbox = new TestMailbox(DESTINATION);

        lsp7 = new LSP7Mock(NAME, SYMBOL, address(this), TOTAL_SUPPLY);
        collateralToken = new HypLSP7Collateral(address(lsp7), address(localMailbox));
        collateralToken.initialize(address(noopHook), address(0), OWNER);

        noopHook = new TestPostDispatchHook();
        localMailbox.setDefaultHook(address(noopHook));
        localMailbox.setRequiredHook(address(noopHook));

        remoteMailbox.setDefaultHook(address(noopHook));
        remoteMailbox.setRequiredHook(address(noopHook));

        syntheticToken = new HypLSP7(DECIMALS, address(remoteMailbox));

        syntheticToken.initialize(0, NAME, SYMBOL, address(noopHook), address(0), OWNER, "");

        vm.startPrank(OWNER);
        syntheticToken.enrollRemoteRouter(ORIGIN, address(collateralToken).addressToBytes32());
        collateralToken.enrollRemoteRouter(DESTINATION, address(syntheticToken).addressToBytes32());
        vm.stopPrank();
    }

    function bridgeToSynthetic() public {
        // Emulate Transfer of `amount` to HypLSP7Collateral
        lsp7.mintTo(address(collateralToken), amount);

        // Bridge (ie Mint) the amount stored in collateral
        bytes memory _body = TokenMessage.format(ATTACKER.addressToBytes32(), amount, "");
        remoteMailbox.testHandle(
            ORIGIN, address(collateralToken).addressToBytes32(), address(syntheticToken).addressToBytes32(), _body
        );
    }

    function bridgeToAddress(
        bytes32 recipient,
        TokenRouter sender,
        TokenRouter receiver,
        uint32 _fromDomain,
        uint32 _toDomain,
        TestMailbox _destMailbox
    )
        internal
    {
        // bridge `amount` to `recipient`
        vm.prank(ATTACKER);
        sender.transferRemote(_toDomain, recipient, amount);

        // recreate the token message sending to `recipient`
        bytes memory _body = TokenMessage.format(recipient, amount, "");

        _destMailbox.testHandle(
            _fromDomain, address(sender).addressToBytes32(), address(receiver).addressToBytes32(), _body
        );
    }

    function bridgeToken(
        bytes32 recipient,
        TokenRouter sender,
        TokenRouter receiver,
        uint32 _fromDomain,
        uint32 _toDomain,
        TestMailbox _destMailbox
    )
        internal
    {
        // Check the balanceOf Collateral Token with totalSupply of Synthetic
        uint256 collateralBalance1 = lsp7.balanceOf(address(collateralToken));
        uint256 totalSupply1 = syntheticToken.totalSupply();
        vm.assertEq(collateralBalance1, totalSupply1);

        bridgeToAddress(recipient, sender, receiver, _fromDomain, _toDomain, _destMailbox);
    }

    function test_bridgeToCollateralUnknownAddress_NoAccountingError() public {
        bridgeToSynthetic();

        uint256 collateralBalance0 = lsp7.balanceOf(address(collateralToken));
        uint256 totalSupply0 = syntheticToken.totalSupply();

        address NOONE = makeAddr("noop");
        bridgeToken(NOONE.addressToBytes32(), syntheticToken, collateralToken, DESTINATION, ORIGIN, localMailbox);

        uint256 collateralBalance1 = lsp7.balanceOf(address(collateralToken));
        uint256 totalSupply1 = syntheticToken.totalSupply();

        console.log("Previous Balance");
        console.log("balanceOf(collateral)", collateralBalance0);
        console.log("totalSupply()", totalSupply0);
        console.log("Post Balance");
        console.log("balanceOf(collateral)", collateralBalance1);
        console.log("totalSupply()", totalSupply1);

        // When bridging to collateral to an uncontrolled address,
        // the collateral router's balance will reflect the total supply
        vm.assertEq(collateralBalance1, totalSupply1);
        vm.assertEq(totalSupply1, 0);
    }

    function test_bridgeToCollateralRouter_CausesAccountingError() public {
        bridgeToSynthetic();

        vm.expectRevert(InvalidRecipientError.selector);
        vm.prank(ATTACKER);
        syntheticToken.transferRemote(ORIGIN, address(collateralToken).addressToBytes32(), amount);
    }

    function test_bridgeToSynthetic_UnknownAddress() public {
        uint256 collateralBalance0 = lsp7.balanceOf(address(collateralToken));
        uint256 totalSupply0 = syntheticToken.totalSupply();

        lsp7.mintTo(ATTACKER, amount);
        vm.prank(ATTACKER);
        lsp7.authorizeOperator(address(collateralToken), amount, "");

        address NOONE = makeAddr("noop");
        bridgeToken(NOONE.addressToBytes32(), collateralToken, syntheticToken, ORIGIN, DESTINATION, remoteMailbox);

        uint256 collateralBalance1 = lsp7.balanceOf(address(collateralToken));
        uint256 totalSupply1 = syntheticToken.totalSupply();
        console.log("Previous Balance");
        console.log("balanceOf(collateral)", collateralBalance0);
        console.log("totalSupply()", totalSupply0);
        console.log("Post Balance");
        console.log("balanceOf(collateral)", collateralBalance1);
        console.log("totalSupply()", totalSupply1);
        // when bridging from collateral to synthetic the collateral balance
        // should equal the synthetic totalSupply regardless of who the
        // synthetic tokens are minted to
        vm.assertEq(collateralBalance1, totalSupply1);
        vm.assertEq(totalSupply1, amount);
    }

    function test_bridgeToSynthetic_SyntheticTokenAddress() public {
        uint256 collateralBalance0 = lsp7.balanceOf(address(collateralToken));
        uint256 totalSupply0 = syntheticToken.totalSupply();

        lsp7.mintTo(ATTACKER, amount);
        vm.prank(ATTACKER);
        lsp7.authorizeOperator(address(collateralToken), amount, "");

        bridgeToken(
            address(syntheticToken).addressToBytes32(),
            collateralToken,
            syntheticToken,
            ORIGIN,
            DESTINATION,
            remoteMailbox
        );

        uint256 collateralBalance1 = lsp7.balanceOf(address(collateralToken));
        uint256 totalSupply1 = syntheticToken.totalSupply();
        console.log("Previous Balance");
        console.log("balanceOf(collateral)", collateralBalance0);
        console.log("totalSupply()", totalSupply0);
        console.log("Post Balance");
        console.log("balanceOf(collateral)", collateralBalance1);
        console.log("totalSupply()", totalSupply1);
        // when bridging from collateral to synthetic the collateral balance
        // should equal the synthetic totalSupply regardless of who the
        // synthetic tokens are minted to
        vm.assertEq(collateralBalance1, totalSupply1);
        vm.assertEq(totalSupply1, amount);
    }
}
