// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.13;

import { Test } from "forge-std/src/Test.sol";

import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import { TestMailbox } from "@hyperlane-xyz/core/contracts/test/TestMailbox.sol";
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";
import { TokenMessage } from "@hyperlane-xyz/core/contracts/token/libs/TokenMessage.sol";

// Mock + contracts to test
import { HypLSP8 } from "../src/HypLSP8.sol";
import { HypLSP8Collateral } from "../src/HypLSP8Collateral.sol";
import { LSP8Mock } from "./LSP8Mock.sol";
import { PausableIsm } from "../src/ISM/PausableISM.sol";
import { PausableHook } from "../src/ISM/PausableHook.sol";

abstract contract HypTokenTest is Test {
    using TypeCasts for address;

    uint256 internal constant INITIAL_SUPPLY = 10;
    string internal constant NAME = "Hyperlane NFTs";
    string internal constant SYMBOL = "HNFT";

    address internal ALICE = makeAddr("alice");
    address internal BOB = makeAddr("bob");
    address internal OWNER = makeAddr("owner");
    address internal CIRCUIT_BREAKER = makeAddr("circuit_breaker");
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

    PausableHook internal pausableHook;
    PausableIsm internal pausableIsm;

    function setUp() public virtual {
        localMailbox = new TestMailbox(ORIGIN);
        remoteMailbox = new TestMailbox(DESTINATION);

        localPrimaryToken = new LSP8Mock(NAME, SYMBOL, OWNER);

        noopHook = new TestPostDispatchHook();
        localMailbox.setDefaultHook(address(noopHook));
        localMailbox.setRequiredHook(address(noopHook));

        pausableHook = new PausableHook(OWNER);
        pausableIsm = new PausableIsm(OWNER);

        vm.deal(ALICE, 1 ether);
    }

    function _deployRemoteToken() internal {
        remoteToken = new HypLSP8(address(remoteMailbox));
        vm.prank(OWNER);
        remoteToken.initialize(0, address(noopHook), address(0), OWNER, NAME, SYMBOL);
        vm.prank(OWNER);
        remoteToken.enrollRemoteRouter(ORIGIN, address(localToken).addressToBytes32());
    }

    function _setupPausableIsm() internal {
        vm.prank(OWNER);
        remoteToken.setInterchainSecurityModule(address(pausableIsm));

        vm.prank(OWNER);
        pausableIsm.registerCircuitBreaker(CIRCUIT_BREAKER);
    }

    // Setting this as a different function because the hook interferes with other tests
    function _setupPausableHook() internal {
        localMailbox.setRequiredHook(address(pausableHook));

        vm.prank(OWNER);
        pausableHook.registerCircuitBreaker(CIRCUIT_BREAKER);
    }

    function _circuitBreakerPauseIsm() internal {
        if (!pausableIsm.paused()) {
            vm.prank(CIRCUIT_BREAKER);
            pausableIsm.pause();
        }
        assertEq(pausableIsm.paused(), true);
    }

    function _circuitBreakerUnpauseIsm() internal {
        if (pausableIsm.paused()) {
            vm.prank(OWNER);
            pausableIsm.unpause();
        }
        assertEq(pausableIsm.paused(), false);
    }

    function _circuitBreakerPauseHook() internal {
        if (!pausableHook.paused()) {
            vm.prank(CIRCUIT_BREAKER);
            pausableHook.pause();
        }
        assertEq(pausableHook.paused(), true);
    }

    function _circuitBreakerUnpauseHook() internal {
        if (pausableHook.paused()) {
            vm.prank(OWNER);
            pausableHook.unpause();
        }
        assertEq(pausableHook.paused(), false);
    }

    function _processTransfers(address _recipient, bytes32 _tokenId) internal {
        vm.prank(address(remoteMailbox));
        remoteToken.handle(
            ORIGIN, address(localToken).addressToBytes32(), abi.encodePacked(_recipient.addressToBytes32(), _tokenId)
        );
    }

    function _performRemoteTransfer(uint256 _msgValue, bytes32 _tokenId) internal {
        vm.prank(ALICE);
        localToken.transferRemote{ value: _msgValue }(DESTINATION, BOB.addressToBytes32(), uint256(_tokenId));
        _processTransfers(BOB, _tokenId);
        assertEq(remoteToken.balanceOf(BOB), 1);
    }

    // This is a work around for creating a message to Mailbox.process()
    // that doesn't use Message.formatMessage because that requires calldata
    // that foundry really doesn't like
    function _formatMessage(
        uint8 _version,
        uint32 _nonce,
        uint32 _originDomain,
        bytes32 _sender,
        uint32 _destinationDomain,
        bytes32 _recipient,
        bytes memory _messageBody // uses memory instead of calldata ftw
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(_version, _nonce, _originDomain, _sender, _destinationDomain, _recipient, _messageBody);
    }

    function _prepareProcessCall(bytes32 _tokenId) internal returns (bytes memory) {
        // ============== WTF IS THIS ? ===========================
        // To test whether the ISM is Paused we must call
        // Mailbox.process(_metadata, _message) on the destination side
        // calling remoteToken.handle() finalizes the cross chain transfer
        // and is only called if the ISM.verify() function returns true
        // so that method cannot be used here
        bytes memory _tokenMessage = TokenMessage.format(BOB.addressToBytes32(), uint256(_tokenId), "");
        bytes32 remoteTokenAddress = address(remoteToken).addressToBytes32();
        bytes32 localRouter = remoteToken.routers(ORIGIN);
        bytes32 localTokenAddress = address(localToken).addressToBytes32();
        assertEq(localRouter, localTokenAddress);

        // solhint-disable-line no-spaces-before-semicolon
        bytes memory message = _formatMessage(
            3, // _version
            1, // _nonce
            ORIGIN, // _originDomain
            localTokenAddress, // _sender is the Router of ORIGIN
            DESTINATION, // _destinationDomain
            remoteTokenAddress, // _recipient is the remote HypLSP7
            _tokenMessage //_messageBody IS instructions on how much to send to what address
        );

        return message;
    }

    function _performRemoteTransferPauseRevert(uint256 _msgValue, bytes32 _tokenId) internal {
        _circuitBreakerPauseIsm();
        vm.prank(ALICE);
        localToken.transferRemote{ value: _msgValue }(DESTINATION, BOB.addressToBytes32(), uint256(_tokenId));
        bytes memory _message = _prepareProcessCall(_tokenId);
        vm.expectRevert("Pausable: paused");
        remoteMailbox.process("", _message); // we don't need metadata
    }

    function _performRemoteTransferNoPause(uint256 _msgValue, bytes32 _tokenId) internal {
        _circuitBreakerUnpauseIsm();
        vm.prank(ALICE);
        localToken.transferRemote{ value: _msgValue }(DESTINATION, BOB.addressToBytes32(), uint256(_tokenId));
        bytes memory _message = _prepareProcessCall(_tokenId);
        remoteMailbox.process("", _message); // we don't need metadata
    }
}

contract HypLSP8Test is HypTokenTest {
    using TypeCasts for address;

    HypLSP8 internal hypLSP8Token;

    function setUp() public override {
        super.setUp();

        localToken = new HypLSP8(address(localMailbox));
        hypLSP8Token = HypLSP8(payable(address(localToken)));

        vm.prank(OWNER);
        hypLSP8Token.initialize(INITIAL_SUPPLY, address(noopHook), address(0), OWNER, NAME, SYMBOL);

        vm.prank(OWNER);
        hypLSP8Token.enrollRemoteRouter(DESTINATION, address(remoteToken).addressToBytes32());

        // Give accounts some ETH for gas
        vm.deal(OWNER, 1 ether);
        vm.deal(ALICE, 1 ether);
        vm.deal(BOB, 1 ether);

        // Transfer some tokens to ALICE for testing
        vm.prank(OWNER);
        hypLSP8Token.transfer(OWNER, ALICE, TOKEN_ID, true, "");

        _deployRemoteToken();
        _setupPausableIsm();
    }

    function testInitialize_revert_ifAlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        hypLSP8Token.initialize(INITIAL_SUPPLY, address(noopHook), address(0), OWNER, NAME, SYMBOL);
    }

    function testTotalSupply() public view {
        assertEq(hypLSP8Token.totalSupply(), INITIAL_SUPPLY);
    }

    function testTokenOwnerOf() public view {
        assertEq(hypLSP8Token.tokenOwnerOf(TOKEN_ID), ALICE);
    }

    function testLocalTransfer() public {
        vm.prank(ALICE);
        hypLSP8Token.transfer(ALICE, BOB, TOKEN_ID, true, "");
        assertEq(hypLSP8Token.tokenOwnerOf(TOKEN_ID), BOB);
        assertEq(hypLSP8Token.balanceOf(ALICE), 0);
        assertEq(hypLSP8Token.balanceOf(BOB), 1);
    }

    function testRemoteTransferHere() public {
        vm.prank(OWNER);
        remoteToken.enrollRemoteRouter(DESTINATION, address(remoteToken).addressToBytes32());

        _performRemoteTransfer(25_000, TOKEN_ID);
        assertEq(hypLSP8Token.balanceOf(ALICE), 0);
    }

    function testRemoteTransfer_revert_unauthorizedOperator() public {
        vm.prank(OWNER);
        vm.expectRevert("!owner");
        localToken.transferRemote{ value: 25_000 }(DESTINATION, BOB.addressToBytes32(), uint256(TOKEN_ID));
    }

    function testRemoteTransfer_revert_invalidTokenId() public {
        bytes32 invalidTokenId = bytes32(uint256(999));
        vm.expectRevert(abi.encodeWithSignature("LSP8NonExistentTokenId(bytes32)", invalidTokenId));
        _performRemoteTransfer(25_000, invalidTokenId);
    }

    function testRemoteTransfer_paused() public {
        _performRemoteTransferPauseRevert(25_000, TOKEN_ID);
    }

    function testRemoteTransfer_unpaused() public {
        _performRemoteTransferNoPause(25_000, TOKEN_ID);
    }

    function testRemoteTransfer_pausedHook() public {
        _setupPausableHook();
        _circuitBreakerPauseHook();

        address prevOwner = hypLSP8Token.tokenOwnerOf(TOKEN_ID);

        vm.expectRevert("Pausable: paused");
        vm.prank(ALICE);
        localToken.transferRemote{ value: 25_000 }(DESTINATION, BOB.addressToBytes32(), uint256(TOKEN_ID));

        address postOwner = hypLSP8Token.tokenOwnerOf(TOKEN_ID);
        assertEq(prevOwner, postOwner);
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

        // Give accounts some ETH for gas
        vm.deal(OWNER, 1 ether);
        vm.deal(ALICE, 1 ether);
        vm.deal(BOB, 1 ether);

        // Mint test tokens
        vm.startPrank(OWNER);
        localPrimaryToken.mint(OWNER, TOKEN_ID, true, "");
        localPrimaryToken.transfer(OWNER, ALICE, TOKEN_ID, true, "");
        vm.stopPrank();

        _deployRemoteToken();
        _setupPausableIsm();

        // Enroll routers for both chains
        vm.prank(OWNER);
        lsp8Collateral.enrollRemoteRouter(DESTINATION, address(remoteToken).addressToBytes32());
    }

    function testRemoteTransferXYZ() public {
        vm.prank(ALICE);
        localPrimaryToken.authorizeOperator(address(lsp8Collateral), TOKEN_ID, "");
        _performRemoteTransfer(25_000, TOKEN_ID);

        assertEq(localPrimaryToken.tokenOwnerOf(TOKEN_ID), address(lsp8Collateral));
    }

    function testRemoteTransfer_revert_unauthorized() public {
        vm.expectRevert(
            abi.encodeWithSignature("LSP8NotTokenOperator(bytes32,address)", TOKEN_ID, address(lsp8Collateral))
        );
        vm.prank(BOB);
        localToken.transferRemote{ value: 25_000 }(DESTINATION, BOB.addressToBytes32(), uint256(TOKEN_ID));
    }

    function testRemoteTransfer_revert_invalidTokenId() public {
        bytes32 invalidTokenId = bytes32(uint256(999));
        vm.expectRevert(abi.encodeWithSignature("LSP8NonExistentTokenId(bytes32)", invalidTokenId));
        _performRemoteTransfer(25_000, invalidTokenId);
    }

    function testRemoteTransferIsmCollateral_paused() public {
        assertEq(localPrimaryToken.tokenOwnerOf(TOKEN_ID), ALICE);

        vm.prank(ALICE);
        localPrimaryToken.authorizeOperator(address(lsp8Collateral), TOKEN_ID, "");
        _performRemoteTransferPauseRevert(25_000, TOKEN_ID);
    }

    function testRemoteTransferIsmCollateral_unpaused() public {
        assertEq(localPrimaryToken.tokenOwnerOf(TOKEN_ID), ALICE);

        vm.prank(ALICE);
        localPrimaryToken.authorizeOperator(address(lsp8Collateral), TOKEN_ID, "");

        _performRemoteTransferNoPause(25_000, TOKEN_ID);
        assertEq(localPrimaryToken.tokenOwnerOf(TOKEN_ID), address(localToken));
        assertEq(remoteToken.tokenOwnerOf(TOKEN_ID), BOB);
    }

    function testRemoteTransferCollateral_pausedHook() public {
        vm.prank(ALICE);
        localPrimaryToken.authorizeOperator(address(lsp8Collateral), TOKEN_ID, "");

        _setupPausableHook();
        _circuitBreakerPauseHook();

        address prevOwner = localPrimaryToken.tokenOwnerOf(TOKEN_ID);

        vm.expectRevert("Pausable: paused");
        vm.prank(ALICE);
        localToken.transferRemote{ value: 25_000 }(DESTINATION, BOB.addressToBytes32(), uint256(TOKEN_ID));

        address postOwner = localPrimaryToken.tokenOwnerOf(TOKEN_ID);
        assertEq(prevOwner, postOwner);
    }
}
