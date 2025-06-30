// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.13;

// test utilities
import { Vm } from "forge-std/src/Vm.sol";
import { HypNFTCollectionTest } from "./HypNFTCollectionTest.sol";

// - Hyperlane types and modules
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";

// Mock + contracts to test
import { HypLSP8 } from "../src/HypLSP8.sol";
import { HypLSP8Collateral } from "../src/HypLSP8Collateral.sol";
import { LSP8Mock } from "./Mocks/LSP8Mock.sol";
import { IERC725Y } from "@erc725/smart-contracts/contracts/interfaces/IERC725Y.sol";

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
import { _LSP8_TOKENID_FORMAT_KEY } from "@lukso/lsp8-contracts/contracts/LSP8Constants.sol";

// errors
import {
    LSP4TokenNameNotEditable,
    LSP4TokenSymbolNotEditable,
    LSP4TokenTypeNotEditable
} from "@lukso/lsp4-contracts/contracts/LSP4Errors.sol";
import { ERC725Y_DataKeysValuesLengthMismatch } from "@erc725/smart-contracts/contracts/errors.sol";

// constants
uint256 constant INITIAL_SUPPLY = 10;
bytes32 constant TOKEN_ID = bytes32(uint256(1));
string constant URI = "http://example.com/token/";

contract HypLSP8Test is HypNFTCollectionTest {
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
        hypLSP8Token.enrollRemoteRouter(DESTINATION, TypeCasts.addressToBytes32(address(remoteToken)));

        // Give accounts some ETH for gas
        vm.deal(OWNER, 1 ether);
        vm.deal(ALICE, 1 ether);
        vm.deal(BOB, 1 ether);

        // Transfer some tokens to ALICE for testing
        vm.prank(OWNER);
        hypLSP8Token.transfer(OWNER, ALICE, TOKEN_ID, true, "");

        _deployRemoteToken();
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

    function testNoDataChangedEventEmittedIfNoDataKeysValuesProvided() public {
        // Capture logs before the transaction
        vm.recordLogs();

        HypLSP8 someHypLSP8Token = new HypLSP8(address(localMailbox));

        // initialize token without setting any additional data key / value pairs
        bytes32[] memory dataKeys = new bytes32[](0);
        bytes[] memory dataValues = new bytes[](0);
        vm.prank(OWNER);
        someHypLSP8Token.initialize(
            INITIAL_SUPPLY, NAME, SYMBOL, address(noopHook), address(0), OWNER, dataKeys, dataValues
        );

        // Search all the logs
        Vm.Log[] memory emittedEvents = vm.getRecordedLogs();
        for (uint256 i = 0; i < emittedEvents.length; i++) {
            // Check that no `DataChanged` event was emitted except for the ones set by:
            // - `LSP4DigitalAssetMetadata` contract in the inheritance
            // - LSP8 Token ID Format
            if (bytes32(emittedEvents[i].topics[0]) == IERC725Y.DataChanged.selector) {
                bool isLSP4SupportedStandardUpdate = emittedEvents[i].topics[1] == _LSP4_SUPPORTED_STANDARDS_KEY;
                bool isLSP4TokenNameUpdate = emittedEvents[i].topics[1] == _LSP4_TOKEN_NAME_KEY;
                bool isLSP4TokenSymbolUpdate = emittedEvents[i].topics[1] == _LSP4_TOKEN_SYMBOL_KEY;
                bool isLSP4TokenTypeUpdate = emittedEvents[i].topics[1] == _LSP4_TOKEN_TYPE_KEY;
                bool isLSP8TokenIdFormatUpdate = emittedEvents[i].topics[1] == _LSP8_TOKENID_FORMAT_KEY;

                assertTrue(
                    isLSP4SupportedStandardUpdate || isLSP4TokenNameUpdate || isLSP4TokenSymbolUpdate
                        || isLSP4TokenTypeUpdate || isLSP8TokenIdFormatUpdate,
                    "No DataChanged event should have been emitted except for the data keys set in `LSP4DigitalAssetMetadata` parent contract and the `LSP8TokenIdFormat` data key"
                );
            }
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
        remoteToken.enrollRemoteRouter(DESTINATION, TypeCasts.addressToBytes32(address(remoteToken)));

        _performRemoteTransfer(25_000, TOKEN_ID);
        assertEq(hypLSP8Token.balanceOf(ALICE), 0);
    }

    function testRemoteTransfer_revert_unauthorizedOperator() public {
        vm.prank(OWNER);
        vm.expectRevert("!owner");
        localToken.transferRemote{ value: 25_000 }(DESTINATION, TypeCasts.addressToBytes32(BOB), uint256(TOKEN_ID));
    }

    function testRemoteTransfer_revert_invalidTokenId() public {
        bytes32 invalidTokenId = bytes32(uint256(999));
        vm.expectRevert(abi.encodeWithSignature("LSP8NonExistentTokenId(bytes32)", invalidTokenId));
        _performRemoteTransfer(25_000, invalidTokenId);
    }
}

contract HypLSP8CollateralTest is HypNFTCollectionTest {
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

        // Enroll routers for both chains
        vm.prank(OWNER);
        lsp8Collateral.enrollRemoteRouter(DESTINATION, TypeCasts.addressToBytes32(address(remoteToken)));
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
        localToken.transferRemote{ value: 25_000 }(DESTINATION, TypeCasts.addressToBytes32(BOB), uint256(TOKEN_ID));
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
    }
}
