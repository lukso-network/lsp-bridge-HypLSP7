// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// test utilities
import { Vm } from "forge-std/src/Vm.sol";
import { Test } from "forge-std/src/Test.sol";
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import { TestMailbox } from "@hyperlane-xyz/core/contracts/test/TestMailbox.sol";
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";
import { TestIsm } from "@hyperlane-xyz/core/contracts/test/TestIsm.sol";
import { formatHyperlaneMessage } from "./helpers/Utils.sol";

// libraries
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";
import { TokenMessage } from "@hyperlane-xyz/core/contracts/token/libs/TokenMessage.sol";

// Mock + contracts to test
import { HypLSP8Pausable } from "../src/pausable/HypLSP8Pausable.sol";
import { HypLSP8CollateralPausable } from "../src/pausable/HypLSP8CollateralPausable.sol";
import { LSP8Mock } from "./helpers/LSP8Mock.sol";
import { Freezable } from "../src/pausable/Freezable.sol";

// constants
import { _LSP4_METADATA_KEY } from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";
import { IERC725Y } from "@erc725/smart-contracts/contracts/interfaces/IERC725Y.sol";
import { _LSP4_METADATA_KEY } from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";
import { _INTERFACEID_LSP0 } from "@lukso/lsp0-contracts/contracts/LSP0Constants.sol";
import {
    _LSP4_TOKEN_TYPE_TOKEN,
    _LSP4_SUPPORTED_STANDARDS_KEY,
    _LSP4_TOKEN_NAME_KEY,
    _LSP4_TOKEN_SYMBOL_KEY,
    _LSP4_TOKEN_TYPE_KEY,
    _LSP4_CREATORS_ARRAY_KEY,
    _LSP4_CREATORS_MAP_KEY_PREFIX,
    _LSP4_METADATA_KEY
} from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";

abstract contract HypTokenPausableTest is Test {
    using TypeCasts for address;

    uint256 internal constant INITIAL_SUPPLY = 10;
    string internal constant NAME = "Hyperlane NFTs";
    string internal constant SYMBOL = "HNFT";

    address internal ALICE = makeAddr("alice");
    address internal BOB = makeAddr("bob");
    address internal OWNER = makeAddr("owner");
    address internal FREEZER = makeAddr("freezer");
    uint32 internal constant ORIGIN = 11;
    uint32 internal constant DESTINATION = 22;
    bytes32 internal constant TOKEN_ID = bytes32(uint256(1));
    string internal constant URI = "http://example.com/token/";
    bytes internal constant SAMPLE_METADATA_BYTES =
        hex"00006f357c6a0020820464ddfac1bec070cc14a8daf04129871d458f2ca94368aae8391311af6361696670733a2f2f516d597231564a4c776572673670456f73636468564775676f3339706136727963455a4c6a7452504466573834554178";

    LSP8Mock internal localPrimaryToken;
    LSP8Mock internal remotePrimaryToken;
    TestMailbox internal localMailbox;
    TestMailbox internal remoteMailbox;
    TokenRouter internal localToken;
    HypLSP8Pausable internal remoteToken;
    TestPostDispatchHook internal noopHook;
    TestIsm internal testIsm;

    function setUp() public virtual {
        localMailbox = new TestMailbox(ORIGIN);
        remoteMailbox = new TestMailbox(DESTINATION);

        localPrimaryToken = new LSP8Mock(NAME, SYMBOL, OWNER);

        noopHook = new TestPostDispatchHook();
        testIsm = new TestIsm();
        localMailbox.setDefaultHook(address(noopHook));
        localMailbox.setRequiredHook(address(noopHook));
        localMailbox.setDefaultIsm(address(testIsm));
        remoteMailbox.setDefaultIsm(address(testIsm));

        vm.deal(ALICE, 1 ether);
    }

    function _deployRemoteToken() internal {
        remoteToken = new HypLSP8Pausable(address(remoteMailbox));

        vm.startPrank(OWNER);
        remoteToken.initialize(0, NAME, SYMBOL, address(noopHook), address(testIsm), OWNER);

        remoteToken.enrollRemoteRouter(ORIGIN, address(localToken).addressToBytes32());

        // post initialize Freezer
        remoteToken.changeFreezer(FREEZER);
        vm.stopPrank();
    }

    function _pauseLocal() internal {
        Freezable _localToken = Freezable(address(localToken));
        if (!_localToken.paused()) {
            vm.prank(FREEZER);
            _localToken.pause();
        }
        assertEq(_localToken.paused(), true);
    }

    function _unpauseLocal() internal {
        Freezable _localToken = Freezable(address(localToken));
        if (_localToken.paused()) {
            vm.prank(OWNER);
            _localToken.unpause();
        }
        assertEq(_localToken.paused(), false);
    }

    function _pauseRemote() internal {
        if (!remoteToken.paused()) {
            vm.prank(FREEZER);
            remoteToken.pause();
        }
        assertEq(remoteToken.paused(), true);
    }

    function _unpauseRemote() internal {
        if (remoteToken.paused()) {
            vm.prank(OWNER);
            remoteToken.unpause();
        }
        assertEq(remoteToken.paused(), false);
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
        bytes memory message = formatHyperlaneMessage(
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
        _pauseRemote();
        vm.prank(ALICE);
        localToken.transferRemote{ value: _msgValue }(DESTINATION, BOB.addressToBytes32(), uint256(_tokenId));
        bytes memory _message = _prepareProcessCall(_tokenId);
        vm.expectRevert("Pausable: paused");
        remoteMailbox.process("", _message); // we don't need metadata
    }

    function _performRemoteTransferNoPause(uint256 _msgValue, bytes32 _tokenId) internal {
        _unpauseRemote();
        vm.prank(ALICE);
        localToken.transferRemote{ value: _msgValue }(DESTINATION, BOB.addressToBytes32(), uint256(_tokenId));
        bytes memory _message = _prepareProcessCall(_tokenId);
        remoteMailbox.process("", _message); // we don't need metadata
    }
}

contract HypLSP8PausableTest is HypTokenPausableTest {
    using TypeCasts for address;

    HypLSP8Pausable internal hypLSP8Token;

    function setUp() public override {
        super.setUp();

        localToken = new HypLSP8Pausable(address(localMailbox));
        hypLSP8Token = HypLSP8Pausable(payable(address(localToken)));

        vm.startPrank(OWNER);
        hypLSP8Token.initialize(INITIAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(testIsm), OWNER);

        hypLSP8Token.enrollRemoteRouter(DESTINATION, address(remoteToken).addressToBytes32());

        // post initialize Freezer
        hypLSP8Token.changeFreezer(FREEZER);
        vm.stopPrank();

        // Give accounts some ETH for gas
        vm.deal(OWNER, 1 ether);
        vm.deal(ALICE, 1 ether);
        vm.deal(BOB, 1 ether);

        // Transfer some tokens to ALICE for testing
        vm.prank(OWNER);
        hypLSP8Token.transfer(OWNER, ALICE, TOKEN_ID, true, "");

        _deployRemoteToken();
    }

    // TODO: add fuzzing parameter
    function testInitialize_revert_ifAlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        hypLSP8Token.initialize(INITIAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), OWNER);
    }

    function testLSP4MetadataIsSet() public view {
        assertEq(hypLSP8Token.getData(_LSP4_METADATA_KEY), SAMPLE_METADATA_BYTES);
    }

    // TODO: change this test since we don't set data keys and values in the initialize(...) function anymore
    function testEmitDataChangedEventWhenMetadataBytesProvided() public {
        vm.skip(true);
        vm.prank(OWNER);
        HypLSP8Pausable someHypLSP8Token = new HypLSP8Pausable(address(localMailbox));

        vm.expectEmit({ checkTopic1: true, checkTopic2: false, checkTopic3: false, checkData: true });
        emit IERC725Y.DataChanged(_LSP4_METADATA_KEY, SAMPLE_METADATA_BYTES);

        // (bytes32[] memory dataKeys, bytes[] memory dataValues) = _getInitDataKeysAndValues();

        someHypLSP8Token.initialize(INITIAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), OWNER);
    }

    // TODO: change this test since we don't set data keys and values in the initialize(...) function anymore
    function testNoDataChangedEventEmittedIfNoMetadataBytesProvided() public {
        vm.skip(true);
        // Capture logs before the transaction
        vm.recordLogs();

        HypLSP8Pausable someHypLSP8Token = new HypLSP8Pausable(address(localMailbox));

        // (bytes32[] memory dataKeys, bytes[] memory dataValues) = (new bytes32[](0), new bytes[](0));

        // initialize token without metadata bytes
        vm.prank(OWNER);
        someHypLSP8Token.initialize(INITIAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), OWNER);

        // Search all the logs
        Vm.Log[] memory emittedEvents = vm.getRecordedLogs();
        for (uint256 i = 0; i < emittedEvents.length; i++) {
            // Check that no `DataChanged` event was emitted for the `LSP4Metadata` data key
            bool hasUpdatedLSP4MetadataKey = bytes32(emittedEvents[i].topics[0]) == IERC725Y.DataChanged.selector
                && emittedEvents[i].topics[1] == _LSP4_METADATA_KEY;

            assertFalse(
                hasUpdatedLSP4MetadataKey,
                "DataChanged event should not have been emitted because no metadata bytes were provided"
            );
        }
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

    function testRemoteTransfer_LocalPaused() public {
        _pauseLocal();

        address prevOwner = hypLSP8Token.tokenOwnerOf(TOKEN_ID);

        vm.expectRevert("Pausable: paused");
        vm.prank(ALICE);
        localToken.transferRemote{ value: 25_000 }(DESTINATION, BOB.addressToBytes32(), uint256(TOKEN_ID));

        address postOwner = hypLSP8Token.tokenOwnerOf(TOKEN_ID);
        assertEq(prevOwner, postOwner);
    }

    function testRemoteTransferToSyntheticLocalPaused() public {
        _pauseLocal();

        assertEq(remoteToken.balanceOf(BOB), 0);
        uint256 aliceBalance = localToken.balanceOf(ALICE);

        vm.expectRevert("Pausable: paused");
        vm.prank(ALICE);
        localToken.transferRemote(DESTINATION, BOB.addressToBytes32(), uint256(TOKEN_ID));

        assertEq(aliceBalance, localToken.balanceOf(ALICE));
    }

    function testTransferToSyntheticRemotePaused() public {
        _pauseRemote();

        bytes memory _message = TokenMessage.format(BOB.addressToBytes32(), uint256(TOKEN_ID), "");
        vm.expectRevert("Pausable: paused");
        vm.prank(ALICE);
        remoteMailbox.testHandle(
            ORIGIN, address(localToken).addressToBytes32(), address(remoteToken).addressToBytes32(), _message
        );
    }
}

contract HypLSP8CollateralPausableTest is HypTokenPausableTest {
    using TypeCasts for address;

    HypLSP8CollateralPausable internal lsp8Collateral;

    function setUp() public override {
        super.setUp();

        localToken = new HypLSP8CollateralPausable(address(localPrimaryToken), address(localMailbox));
        lsp8Collateral = HypLSP8CollateralPausable(address(localToken));

        lsp8Collateral.initialize(address(noopHook), address(testIsm), OWNER);

        vm.prank(OWNER);
        lsp8Collateral.changeFreezer(FREEZER);

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

    function testTransferToCollateral_LocalPaused() public {
        _pauseLocal();

        bytes memory _message = TokenMessage.format(BOB.addressToBytes32(), uint256(TOKEN_ID), "");
        vm.expectRevert("Pausable: paused");
        localMailbox.testHandle(
            DESTINATION, address(remoteToken).addressToBytes32(), address(localToken).addressToBytes32(), _message
        );
    }

    function testTransferToCollateralRemotePaused() public {
        _pauseRemote();

        assertEq(remoteToken.balanceOf(BOB), 0);
        uint256 aliceBalance = localToken.balanceOf(ALICE);

        vm.expectRevert("Pausable: paused");
        vm.prank(ALICE);
        remoteToken.transferRemote(DESTINATION, BOB.addressToBytes32(), uint256(TOKEN_ID));

        assertEq(aliceBalance, localToken.balanceOf(ALICE));
    }

    function testNoLSP8CircuitBreakerDoesNotCauseRevert() public {
        // vm.prank(address(this));
        HypLSP8CollateralPausable lsp8CollateralNoFreezer =
            new HypLSP8CollateralPausable(address(localPrimaryToken), address(localMailbox));
        lsp8CollateralNoFreezer.initialize(address(noopHook), address(testIsm), OWNER);

        vm.prank(OWNER);
        lsp8CollateralNoFreezer.enrollRemoteRouter(DESTINATION, address(remoteToken).addressToBytes32());

        bytes32 TOKEN_ID_2 = hex"02";
        localPrimaryToken.mint(address(lsp8CollateralNoFreezer), TOKEN_ID_2, true, "");

        bytes memory _message = TokenMessage.format(BOB.addressToBytes32(), uint256(TOKEN_ID_2), "");

        localMailbox.testHandle(
            DESTINATION,
            address(remoteToken).addressToBytes32(),
            address(lsp8CollateralNoFreezer).addressToBytes32(),
            _message
        );
    }
}
