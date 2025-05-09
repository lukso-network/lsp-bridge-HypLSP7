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
import { LSP8Mock } from "../Mocks/LSP8Mock.sol";
import { HypLSP8 } from "../../src/HypLSP8.sol";
import { HypLSP8Collateral } from "../../src/HypLSP8Collateral.sol";

contract CollateralImbalanceLSP8 is Test {
    using TypeCasts for address;
    using TokenMessage for bytes;

    error InvalidRecipientError();

    address internal ATTACKER = makeAddr("attacker");
    address internal OWNER = makeAddr("owner");

    LSP8Mock internal lsp8;
    HypLSP8Collateral internal collateralToken;
    HypLSP8 internal syntheticToken;

    TestMailbox internal localMailbox;
    TestMailbox internal remoteMailbox;
    TestPostDispatchHook internal noopHook;

    uint32 internal constant ORIGIN = 11;
    uint32 internal constant DESTINATION = 12;

    string internal constant NAME = "HyperlaneInu";
    string internal constant SYMBOL = "HYP";

    uint256 internal tokenId = 0; // always increments before minting so first minted tokenId will be 1

    function setUp() public {
        localMailbox = new TestMailbox(ORIGIN);
        remoteMailbox = new TestMailbox(DESTINATION);

        lsp8 = new LSP8Mock(NAME, SYMBOL, address(this));
        collateralToken = new HypLSP8Collateral(address(lsp8), address(localMailbox));
        collateralToken.initialize(address(noopHook), address(0), OWNER);

        noopHook = new TestPostDispatchHook();
        localMailbox.setDefaultHook(address(noopHook));
        localMailbox.setRequiredHook(address(noopHook));

        remoteMailbox.setDefaultHook(address(noopHook));
        remoteMailbox.setRequiredHook(address(noopHook));

        syntheticToken = new HypLSP8(address(remoteMailbox));

        syntheticToken.initialize(0, NAME, SYMBOL, address(noopHook), address(0), OWNER, "");

        vm.startPrank(OWNER);
        syntheticToken.enrollRemoteRouter(ORIGIN, address(collateralToken).addressToBytes32());
        collateralToken.enrollRemoteRouter(DESTINATION, address(syntheticToken).addressToBytes32());
        vm.stopPrank();
    }

    function bridgeToSynthetic(uint256 _tokenId) public {
        // Emulate Transfer of `tokenId` to HypLSP7Collateral
        lsp8.mint(address(collateralToken), bytes32(_tokenId), true, "");

        // Bridge (ie Mint) the tokenId stored in collateral
        bytes memory _body = TokenMessage.format(ATTACKER.addressToBytes32(), _tokenId, "");
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
        TestMailbox _destMailbox,
        uint256 _tokenId
    )
        internal
    {
        // bridge `tokenId` to `recipient`
        vm.prank(ATTACKER);
        sender.transferRemote(_toDomain, recipient, _tokenId);

        // recreate the token message sending to `recipient`
        bytes memory _body = TokenMessage.format(recipient, _tokenId, "");

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
        TestMailbox _destMailbox,
        uint256 _tokenId
    )
        internal
    {
        // Check the balanceOf Collateral Token with totalSupply of Synthetic
        uint256 collateralBalance1 = lsp8.balanceOf(address(collateralToken));
        uint256 totalSupply1 = syntheticToken.totalSupply();
        vm.assertEq(collateralBalance1, totalSupply1);

        bridgeToAddress(recipient, sender, receiver, _fromDomain, _toDomain, _destMailbox, _tokenId);
    }

    function test_bridgeToCollateralUnknownAddress_NoAccountingError() public {
        tokenId += 1;
        bridgeToSynthetic(tokenId);

        uint256 collateralBalance0 = lsp8.balanceOf(address(collateralToken));
        uint256 totalSupply0 = syntheticToken.totalSupply();

        address NOONE = makeAddr("noop");
        bridgeToken(
            NOONE.addressToBytes32(), syntheticToken, collateralToken, DESTINATION, ORIGIN, localMailbox, tokenId
        );

        uint256 collateralBalance1 = lsp8.balanceOf(address(collateralToken));
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
        tokenId += 1;
        bridgeToSynthetic(tokenId);

        uint256 collateralBalance0 = lsp8.balanceOf(address(collateralToken));
        uint256 totalSupply0 = syntheticToken.totalSupply();

        vm.expectRevert(InvalidRecipientError.selector);
        vm.prank(ATTACKER);
        syntheticToken.transferRemote(ORIGIN, address(collateralToken).addressToBytes32(), tokenId);
    }

    function test_bridgeToSynthetic_UnknownAddress() public {
        uint256 collateralBalance0 = lsp8.balanceOf(address(collateralToken));
        uint256 totalSupply0 = syntheticToken.totalSupply();

        tokenId += 1;
        lsp8.mint(ATTACKER, bytes32(tokenId), true, "");
        vm.prank(ATTACKER);
        lsp8.authorizeOperator(address(collateralToken), bytes32(tokenId), "");

        address NOONE = makeAddr("noop");
        bridgeToken(
            NOONE.addressToBytes32(), collateralToken, syntheticToken, ORIGIN, DESTINATION, remoteMailbox, tokenId
        );

        uint256 collateralBalance1 = lsp8.balanceOf(address(collateralToken));
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
        vm.assertEq(totalSupply1, tokenId);
    }

    function test_bridgeToSynthetic_SyntheticTokenAddress() public {
        uint256 collateralBalance0 = lsp8.balanceOf(address(collateralToken));
        uint256 totalSupply0 = syntheticToken.totalSupply();

        tokenId += 1;
        lsp8.mint(ATTACKER, bytes32(tokenId), true, "");
        vm.prank(ATTACKER);
        lsp8.authorizeOperator(address(collateralToken), bytes32(tokenId), "");

        bridgeToken(
            address(syntheticToken).addressToBytes32(),
            collateralToken,
            syntheticToken,
            ORIGIN,
            DESTINATION,
            remoteMailbox,
            tokenId
        );

        uint256 collateralBalance1 = lsp8.balanceOf(address(collateralToken));
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
        vm.assertEq(totalSupply1, tokenId);
    }
}
