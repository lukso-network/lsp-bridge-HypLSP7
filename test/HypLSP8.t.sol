// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.13;

// test utilities
import { Vm } from "forge-std/src/Vm.sol";
import { Test } from "forge-std/src/Test.sol";
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import { TestMailbox } from "@hyperlane-xyz/core/contracts/test/TestMailbox.sol";
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";

// libraries
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";
import { TokenMessage } from "@hyperlane-xyz/core/contracts/token/libs/TokenMessage.sol";

// Mock + contracts to test
import { HypLSP8 } from "../src/HypLSP8.sol";
import { HypLSP8Collateral } from "../src/HypLSP8Collateral.sol";
import { LSP8Mock } from "./Mocks/LSP8Mock.sol";
import { PausableCircuitBreakerIsm } from "../src/ISM/PausableCircuitBreakerISM.sol";
import { PausableCircuitBreakerHook } from "../src/ISM/PausableCircuitBreakerHook.sol";
import { IERC725Y } from "@erc725/smart-contracts/contracts/interfaces/IERC725Y.sol";

// constants
import { _INTERFACEID_LSP0 } from "@lukso/lsp0-contracts/contracts/LSP0Constants.sol";
import {
    _LSP4_TOKEN_TYPE_TOKEN,
    _LSP4_TOKEN_NAME_KEY,
    _LSP4_TOKEN_SYMBOL_KEY,
    _LSP4_TOKEN_TYPE_KEY,
    _LSP4_CREATORS_ARRAY_KEY,
    _LSP4_CREATORS_MAP_KEY_PREFIX,
    _LSP4_METADATA_KEY
} from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";

// errors
import {
    LSP4TokenNameNotEditable,
    LSP4TokenSymbolNotEditable,
    LSP4TokenTypeNotEditable
} from "@lukso/lsp4-contracts/contracts/LSP4Errors.sol";
import { ERC725Y_DataKeysValuesLengthMismatch } from "@erc725/smart-contracts/contracts/errors.sol";

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
    bytes internal constant SAMPLE_METADATA_BYTES =
        hex"00006f357c6a0020820464ddfac1bec070cc14a8daf04129871d458f2ca94368aae8391311af6361696670733a2f2f516d597231564a4c776572673670456f73636468564775676f3339706136727963455a4c6a7452504466573834554178";

    LSP8Mock internal localPrimaryToken;
    LSP8Mock internal remotePrimaryToken;
    TestMailbox internal localMailbox;
    TestMailbox internal remoteMailbox;
    TokenRouter internal localToken;
    HypLSP8 internal remoteToken;
    TestPostDispatchHook internal noopHook;

    PausableCircuitBreakerHook internal pausableHook;
    PausableCircuitBreakerIsm internal pausableIsm;

    function setUp() public virtual {
        localMailbox = new TestMailbox(ORIGIN);
        remoteMailbox = new TestMailbox(DESTINATION);

        localPrimaryToken = new LSP8Mock(NAME, SYMBOL, OWNER);

        noopHook = new TestPostDispatchHook();
        localMailbox.setDefaultHook(address(noopHook));
        localMailbox.setRequiredHook(address(noopHook));

        pausableHook = new PausableCircuitBreakerHook(OWNER);
        pausableIsm = new PausableCircuitBreakerIsm(OWNER);

        vm.deal(ALICE, 1 ether);
    }

    function _deployRemoteToken() internal {
        remoteToken = new HypLSP8(address(remoteMailbox));
        vm.prank(OWNER);
        (bytes32[] memory dataKeys, bytes[] memory dataValues) = _getInitDataKeysAndValues();
        remoteToken.initialize(0, NAME, SYMBOL, address(noopHook), address(0), OWNER, dataKeys, dataValues);
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

    // setting data keys for the following:
    // - 1 x creator in the creator array
    // - creator's info under the map key
    // - the token metadata
    function _getInitDataKeysAndValues() internal view returns (bytes32[] memory dataKeys, bytes[] memory dataValues) {
        dataKeys = new bytes32[](4);
        dataKeys[0] = _LSP4_CREATORS_ARRAY_KEY;
        dataKeys[1] = bytes32(abi.encodePacked(bytes16(_LSP4_CREATORS_ARRAY_KEY), bytes16(uint128(0))));
        dataKeys[2] = bytes32(abi.encodePacked(_LSP4_CREATORS_MAP_KEY_PREFIX, bytes2(0), bytes20(msg.sender)));
        dataKeys[3] = _LSP4_METADATA_KEY;

        dataValues = new bytes[](4);
        dataValues[0] = abi.encodePacked(bytes16(uint128(1)));
        dataValues[1] = abi.encodePacked(bytes20(msg.sender));
        dataValues[2] = abi.encodePacked(_INTERFACEID_LSP0, bytes16(uint128(0)));
        dataValues[3] = SAMPLE_METADATA_BYTES;
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
        (bytes32[] memory dataKeys, bytes[] memory dataValues) = _getInitDataKeysAndValues();
        hypLSP8Token.initialize(
            INITIAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), OWNER, dataKeys, dataValues
        );

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

    function test_Initialize_RevertIfAlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        (bytes32[] memory dataKeys, bytes[] memory dataValues) = _getInitDataKeysAndValues();
        hypLSP8Token.initialize(
            INITIAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), OWNER, dataKeys, dataValues
        );
    }

    function test_Initialize_RevertIfDataKeysAndValuesLengthMissmatch() public {
        // Capture logs before the transaction
        vm.recordLogs();

        HypLSP8 someHypLSP8Token = new HypLSP8(address(localMailbox));

        // initialize token without metadata bytes
        vm.prank(OWNER);
        bytes32[] memory dataKeys = new bytes32[](1);
        dataKeys[0] = _LSP4_METADATA_KEY;
        bytes[] memory dataValues = new bytes[](0);

        vm.expectRevert(ERC725Y_DataKeysValuesLengthMismatch.selector);
        someHypLSP8Token.initialize(
            INITIAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), OWNER, dataKeys, dataValues
        );
    }

    function test_SetData_ChangeTokenName_Reverts(bytes memory name) public {
        vm.prank(OWNER);
        vm.expectRevert(LSP4TokenNameNotEditable.selector);
        hypLSP8Token.setData(_LSP4_TOKEN_NAME_KEY, name);
    }

    function test_SetData_ChangeTokenSymbol_Reverts(bytes memory name) public {
        vm.prank(OWNER);
        vm.expectRevert(LSP4TokenSymbolNotEditable.selector);
        hypLSP8Token.setData(_LSP4_TOKEN_SYMBOL_KEY, name);
    }

    function test_SetData_ChangeTokenType_Reverts(bytes memory name) public {
        vm.prank(OWNER);
        vm.expectRevert(LSP4TokenTypeNotEditable.selector);
        hypLSP8Token.setData(_LSP4_TOKEN_TYPE_KEY, name);
    }

    function testInitDataKeysAreSet() public view {
        (bytes32[] memory dataKeys, bytes[] memory dataValues) = _getInitDataKeysAndValues();

        for (uint256 index = 0; index < dataKeys.length; index++) {
            vm.assertEq(hypLSP8Token.getData(dataKeys[index]), dataValues[index]);
        }
    }

    function testEmitDataChangedEventWhenMetadataBytesProvided() public {
        vm.prank(OWNER);
        HypLSP8 someHypLSP8Token = new HypLSP8(address(localMailbox));

        vm.expectEmit({ checkTopic1: true, checkTopic2: false, checkTopic3: false, checkData: true });
        emit IERC725Y.DataChanged(_LSP4_METADATA_KEY, SAMPLE_METADATA_BYTES);

        (bytes32[] memory dataKeys, bytes[] memory dataValues) = _getInitDataKeysAndValues();
        someHypLSP8Token.initialize(
            INITIAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), OWNER, dataKeys, dataValues
        );
    }

    function testNoDataChangedEventEmittedIfNoMetadataBytesProvided() public {
        // Capture logs before the transaction
        vm.recordLogs();

        HypLSP8 someHypLSP8Token = new HypLSP8(address(localMailbox));

        // initialize token without metadata bytes
        bytes32[] memory dataKeys = new bytes32[](0);
        bytes[] memory dataValues = new bytes[](0);
        vm.prank(OWNER);
        someHypLSP8Token.initialize(
            INITIAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), OWNER, dataKeys, dataValues
        );

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
