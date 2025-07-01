// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.21;

// test utilities
import { Test } from "forge-std/src/Test.sol";

// Hyperlane testing environnement

// - Mock test contracts
import { TestMailbox } from "@hyperlane-xyz/core/contracts/test/TestMailbox.sol";
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";
import { TestInterchainGasPaymaster } from "@hyperlane-xyz/core/contracts/test/TestInterchainGasPaymaster.sol";

// - Hyperlane types and modules
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import { GasRouter } from "@hyperlane-xyz/core/contracts/client/GasRouter.sol";

// - Hyperlane libraries
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";
import { TokenMessage } from "@hyperlane-xyz/core/contracts/token/libs/TokenMessage.sol";

// Mock contracts to test
// TODO: these should be changed depending on the direction (ERC20 on Ethereum, lSP7 on LUKSO)
import { LSP8Mock } from "./Mocks/LSP8Mock.sol";
import { HypLSP8 } from "../src/HypLSP8.sol";

// TODO: these should be changed depending on the direction (ERC20 on Ethereum, lSP7 on LUKSO)
// constants
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

/// @dev TODO: write basic description of this test setup
abstract contract HypNFTCollectionTest is Test {
    using TypeCasts for address;

    // origin chain
    // ---------------------------
    uint32 internal constant ORIGIN = 11;
    TokenRouter internal localToken;
    TestMailbox internal localMailbox;

    // destination chain
    // ---------------------------
    uint32 internal constant DESTINATION = 22;
    HypLSP8 internal remoteToken;
    TestMailbox internal remoteMailbox;

    // warp route parameters
    // ---------------------------
    TestPostDispatchHook internal noopHook;

    address internal WARP_ROUTE_OWNER = makeAddr("warp route owner");
    uint256 internal constant INITIAL_SUPPLY = 10;

    // NFT collection being bridged
    // TODO: initialization of this token should be moved in the HypLSP8Test `setUp()` functionAdd commentMore actions
    // ---------------------------
    LSP8Mock internal primaryNFTCollection;

    string internal constant NAME = "Hyperlane NFTs";
    string internal constant SYMBOL = "HNFT";
    string internal constant URI = "http://example.com/token/";
    bytes internal constant SAMPLE_METADATA_BYTES =
        hex"00006f357c6a0020820464ddfac1bec070cc14a8daf04129871d458f2ca94368aae8391311af6361696670733a2f2f516d597231564a4c776572673670456f73636468564775676f3339706136727963455a4c6a7452504466573834554178";

    // constants used for testing
    // ---------------------------
    address internal ALICE = makeAddr("alice");
    address internal BOB = makeAddr("bob");
    bytes32 internal constant TOKEN_ID = bytes32(uint256(1));

    function setUp() public virtual {
        localMailbox = new TestMailbox(ORIGIN);
        remoteMailbox = new TestMailbox(DESTINATION);

        primaryNFTCollection = new LSP8Mock(NAME, SYMBOL, WARP_ROUTE_OWNER);

        noopHook = new TestPostDispatchHook();
        localMailbox.setDefaultHook(address(noopHook));
        localMailbox.setRequiredHook(address(noopHook));

        vm.deal(ALICE, 1 ether);
    }

    function _deployRemoteToken() internal {
        remoteToken = new HypLSP8(address(remoteMailbox));
        vm.prank(WARP_ROUTE_OWNER);
        (bytes32[] memory dataKeys, bytes[] memory dataValues) = _getInitDataKeysAndValues();
        remoteToken.initialize(0, NAME, SYMBOL, address(noopHook), address(0), WARP_ROUTE_OWNER, dataKeys, dataValues);
        vm.prank(WARP_ROUTE_OWNER);
        remoteToken.enrollRemoteRouter(ORIGIN, address(localToken).addressToBytes32());
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

    function _prepareProcessCall(bytes32 _tokenId) internal view returns (bytes memory) {
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
