// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.13;

import { Test } from "forge-std/src/Test.sol";

import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import { TestMailbox } from "@hyperlane-xyz/core/contracts/test/TestMailbox.sol";
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";
import { TestInterchainGasPaymaster } from "@hyperlane-xyz/core/contracts/test/TestInterchainGasPaymaster.sol";
import { GasRouter } from "@hyperlane-xyz/core/contracts/client/GasRouter.sol";
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";

// Mock + contracts to test
import { HypLSP8 } from "../src/HypLSP8.sol";
import { HypLSP8Collateral } from "../src/HypLSP8Collateral.sol";
import { LSP8Mock } from "./LSP8Mock.sol";

import "forge-std/src/console.sol";

abstract contract HypTokenTest is Test {
    using TypeCasts for address;

    uint256 internal constant INITIAL_SUPPLY = 10;
    string internal constant NAME = "Hyperlane NFTs";
    string internal constant SYMBOL = "HNFT";

    address internal ALICE = makeAddr("alice");
    address internal BOB = makeAddr("bob");
    address internal OWNER = makeAddr("owner");
    uint32 internal constant ORIGIN = 11;
    uint32 internal constant DESTINATION = 22;
    bytes32 internal constant TOKEN_ID = bytes32(uint256(1));
    string internal constant URI = "http://example.com/token/";

    LSP8Mock internal localPrimaryToken;
    LSP8Mock internal remotePrimaryToken;
    TestMailbox internal localMailbox;
    TestMailbox internal remoteMailbox;
    TokenRouter internal localToken;
    HypLSP8 internal remoteToken;
    TestPostDispatchHook internal noopHook;
    TestInterchainGasPaymaster internal igp;

    event SentTransferRemote(
        uint32 indexed destination,
        bytes32 indexed recipient,
        bytes32 tokenId
    );

    event ReceivedTransferRemote(
        uint32 indexed origin,
        bytes32 indexed recipient,
        bytes32 tokenId
    );

    function setUp() public virtual {
        localMailbox = new TestMailbox(ORIGIN);
        remoteMailbox = new TestMailbox(DESTINATION);

        localPrimaryToken = new LSP8Mock(NAME, SYMBOL, OWNER);

        noopHook = new TestPostDispatchHook();
        localMailbox.setDefaultHook(address(noopHook));
        localMailbox.setRequiredHook(address(noopHook));

        remoteToken = new HypLSP8(address(remoteMailbox));

        vm.prank(OWNER);
        // remoteToken.initialize(100, NAME, SYMBOL);
        remoteToken.initialize(100, NAME, SYMBOL);

        igp = new TestInterchainGasPaymaster();

        vm.deal(ALICE, 125_000);
    }

    function _enrollRemoteTokenRouter() internal {
        vm.prank(OWNER);
        remoteToken.enrollRemoteRouter(ORIGIN, address(localToken).addressToBytes32());
    }

    function _processTransfers(address _recipient, bytes32 _tokenId) internal {
        vm.prank(address(remoteMailbox));
        remoteToken.handle(
            ORIGIN,
            address(localToken).addressToBytes32(),
            abi.encodePacked(_recipient.addressToBytes32(), _tokenId)
        );
    }

    function _performRemoteTransfer(uint256 _msgValue, bytes32 _tokenId) internal {
        vm.prank(ALICE);
        localToken.transferRemote{ value: _msgValue }(
            DESTINATION,
            BOB.addressToBytes32(),
            uint256(_tokenId)
        );

        vm.expectEmit(true, true, false, true);
        emit ReceivedTransferRemote(ORIGIN, BOB.addressToBytes32(), _tokenId);
        _processTransfers(BOB, _tokenId);

        assertEq(remoteToken.balanceOf(BOB), 1);
    }
}

contract HypLSP8Test is HypTokenTest {
    using TypeCasts for address;

    HypLSP8 internal lsp8Token;

    function setUp() public override {
        super.setUp();

        localToken = new HypLSP8(address(localMailbox));
        lsp8Token = HypLSP8(payable(address(localToken)));

        vm.prank(OWNER);
        lsp8Token.initialize(INITIAL_SUPPLY, NAME, SYMBOL);

        vm.prank(OWNER);
        lsp8Token.enrollRemoteRouter(DESTINATION, address(remoteToken).addressToBytes32());

        // // Transfer some tokens to ALICE for testing
        vm.prank(OWNER);
        lsp8Token.transfer(OWNER, ALICE, TOKEN_ID, true, "");

        // _enrollRemoteTokenRouter();
    }

    function testInitialize_revert_ifAlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        lsp8Token.initialize(INITIAL_SUPPLY, NAME, SYMBOL);
    }

    function testTotalSupply() public {
        assertEq(lsp8Token.totalSupply(), INITIAL_SUPPLY);
    }

    function testTokenOwnerOf() public {
        assertEq(lsp8Token.tokenOwnerOf(TOKEN_ID), ALICE);
    }

    function testLocalTransfer() public {
        vm.prank(ALICE);
        lsp8Token.transfer(ALICE, BOB, TOKEN_ID, true, "");
        assertEq(lsp8Token.tokenOwnerOf(TOKEN_ID), BOB);
        assertEq(lsp8Token.balanceOf(ALICE), 0);
        assertEq(lsp8Token.balanceOf(BOB), 1);
    }

    function testRemoteTransfer() public {
        vm.prank(OWNER);
        remoteToken.enrollRemoteRouter(ORIGIN, address(localToken).addressToBytes32());

        // vm.expectEmit(true, true, false, true);
        // emit SentTransferRemote(DESTINATION, BOB.addressToBytes32(), TOKEN_ID);

        _performRemoteTransfer(25000, TOKEN_ID);
        assertEq(lsp8Token.balanceOf(ALICE), 0);
    }

    function testRemoteTransfer_revert_unauthorizedOperator() public {
        vm.prank(BOB);
        vm.expectRevert("LSP8: caller is not owner nor operator");
        localToken.transferRemote{ value: 25000 }(
            DESTINATION,
            BOB.addressToBytes32(),
            uint256(TOKEN_ID)
        );
    }

    function testRemoteTransfer_revert_invalidTokenId() public {
        bytes32 invalidTokenId = bytes32(uint256(999));
        vm.expectRevert("LSP8: token does not exist");
        _performRemoteTransfer(25000, invalidTokenId);
    }
}

contract HypLSP8CollateralTest is HypTokenTest {
    using TypeCasts for address;

    HypLSP8Collateral internal lsp8Collateral;

    function setUp() public override {
        super.setUp();

        localToken = new HypLSP8Collateral(address(localPrimaryToken), address(localMailbox));
        lsp8Collateral = HypLSP8Collateral(address(localToken));

        vm.prank(OWNER);
        lsp8Collateral.initialize(address(noopHook), address(0), OWNER);

        vm.prank(OWNER);
        lsp8Collateral.enrollRemoteRouter(DESTINATION, address(remoteToken).addressToBytes32());

        // Mint test tokens
        vm.startPrank(OWNER);
        localPrimaryToken.mint(OWNER, TOKEN_ID, true, "");
        localPrimaryToken.transfer(OWNER, ALICE, TOKEN_ID, true, "");
        vm.stopPrank();

        _enrollRemoteTokenRouter();
    }

    function testRemoteTransfer() public {
        vm.prank(ALICE);
        localPrimaryToken.authorizeOperator(address(lsp8Collateral), TOKEN_ID, "");
        _performRemoteTransfer(25000, TOKEN_ID);

        assertEq(localPrimaryToken.tokenOwnerOf(TOKEN_ID), address(lsp8Collateral));
    }

    function testRemoteTransfer_revert_unauthorized() public {
        vm.expectRevert("LSP8: caller is not owner nor operator");
        _performRemoteTransfer(25000, TOKEN_ID);
    }

    function testRemoteTransfer_revert_invalidTokenId() public {
        bytes32 invalidTokenId = bytes32(uint256(999));
        vm.expectRevert("LSP8: token does not exist");
        _performRemoteTransfer(25000, invalidTokenId);
    }
}
