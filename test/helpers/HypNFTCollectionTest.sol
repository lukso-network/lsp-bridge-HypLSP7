// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// test utilities
import { Test } from "forge-std/src/Test.sol";
import { formatHyperlaneMessage } from "./Utils.sol";

// Hyperlane testing environnement

// - Mock test contracts
import { TestMailbox } from "@hyperlane-xyz/core/contracts/test/TestMailbox.sol";
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";

// - Hyperlane types and modules
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";

// - Hyperlane libraries
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";
import { TokenMessage } from "@hyperlane-xyz/core/contracts/token/libs/TokenMessage.sol";

// Mock contracts to test
// TODO: these should be changed depending on the direction (ERC20 on Ethereum, lSP7 on LUKSO)
import { LSP8Mock } from "./LSP8Mock.sol";
import { HypLSP8 } from "../../src/HypLSP8.sol";

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

    address internal immutable WARP_ROUTE_OWNER = makeAddr("warp route owner");
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
    address internal immutable ALICE = makeAddr("alice");
    address internal immutable BOB = makeAddr("bob");
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
        remoteToken.initialize(0, NAME, SYMBOL, address(noopHook), address(0), WARP_ROUTE_OWNER);
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
}
