// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Test } from "forge-std/src/Test.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { TestMailbox } from "@hyperlane-xyz/core/contracts/test/TestMailbox.sol";
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";
import { TestIsm } from "@hyperlane-xyz/core/contracts/test/TestIsm.sol";
import { HypLSP7 } from "../../src/HypLSP7.sol";

import { IERC725Y } from "@erc725/smart-contracts/contracts/interfaces/IERC725Y.sol";
import { generateLSP4DataKeysAndValues } from "../helpers/Utils.sol";

import {
    _LSP4_TOKEN_NAME_KEY,
    _LSP4_TOKEN_SYMBOL_KEY,
    _LSP4_TOKEN_TYPE_KEY
} from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";

// errors
import {
    LSP4TokenNameNotEditable,
    LSP4TokenSymbolNotEditable,
    LSP4TokenTypeNotEditable
} from "@lukso/lsp4-contracts/contracts/LSP4Errors.sol";
import { ERC725Y_DataKeysValuesLengthMismatch } from "@erc725/smart-contracts/contracts/errors.sol";

contract HypLSP7Test is Test {
    // Hyperlane Mailbox
    uint32 constant CHAIN_ID = 42;
    TestMailbox mailbox;

    // Warp route
    TestPostDispatchHook internal defaultHook;
    TestIsm internal defaultIsm;

    string internal constant NAME = "Test USDC";
    string internal constant SYMBOL = "tUSDC";
    uint8 internal constant DECIMALS = 6; // USDC has 6 decimals points
    uint256 internal constant TOTAL_SUPPLY = 1_000_000 * (10 ** DECIMALS);

    uint256 internal constant SCALE_PARAM = 1;

    address internal immutable PROXY_ADMIN = makeAddr("Proxy Admin");
    address internal immutable WARP_ROUTE_OWNER = makeAddr("warp route owner");

    HypLSP7 syntheticToken;

    function setUp() public {
        mailbox = new TestMailbox(CHAIN_ID);

        defaultHook = new TestPostDispatchHook();
        defaultIsm = new TestIsm();

        HypLSP7 implementation = new HypLSP7(DECIMALS, SCALE_PARAM, address(mailbox));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            PROXY_ADMIN,
            abi.encodeCall(
                HypLSP7.initialize,
                (TOTAL_SUPPLY, NAME, SYMBOL, address(defaultHook), address(defaultIsm), WARP_ROUTE_OWNER)
            )
        );

        syntheticToken = HypLSP7(payable(proxy));
    }

    function test_InitializeRevertsIfAlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        syntheticToken.initialize(TOTAL_SUPPLY, NAME, SYMBOL, address(0xdead), address(0xbeef), WARP_ROUTE_OWNER);
    }

    function test_DecimalsIsSet() public view {
        assertEq(syntheticToken.decimals(), DECIMALS);
    }

    /// @dev Fuzz the decimals function to ensure the proxy always get the right decimals value derived from
    /// implementation
    /// when set via the implementation's `constructor`.
    function test_DecimalsFuzz(uint8 decimals) public {
        HypLSP7 implementation = new HypLSP7(decimals, SCALE_PARAM, address(mailbox));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            PROXY_ADMIN,
            abi.encodeCall(
                HypLSP7.initialize,
                (TOTAL_SUPPLY, NAME, SYMBOL, address(defaultHook), address(defaultIsm), WARP_ROUTE_OWNER)
            )
        );

        HypLSP7 hypLSP7Token = HypLSP7(payable(proxy));

        assertEq(hypLSP7Token.decimals(), decimals);
    }

    function testTotalSupply() public view {
        assertEq(syntheticToken.totalSupply(), TOTAL_SUPPLY);
    }

    function test_ChangeTokenName_Reverts(bytes memory name) public {
        vm.prank(WARP_ROUTE_OWNER);
        vm.expectRevert(LSP4TokenNameNotEditable.selector);
        syntheticToken.setData(_LSP4_TOKEN_NAME_KEY, name);
    }

    function test_ChangeTokenSymbol_Reverts(bytes memory name) public {
        vm.prank(WARP_ROUTE_OWNER);
        vm.expectRevert(LSP4TokenSymbolNotEditable.selector);
        syntheticToken.setData(_LSP4_TOKEN_SYMBOL_KEY, name);
    }

    function test_ChangeTokenType_Reverts(bytes memory name) public {
        vm.prank(WARP_ROUTE_OWNER);
        vm.expectRevert(LSP4TokenTypeNotEditable.selector);
        syntheticToken.setData(_LSP4_TOKEN_TYPE_KEY, name);
    }

    function test_OwnerCanSetDataKeysAfterDeployment(bytes32 dataKey, bytes memory dataValue) public {
        vm.assume(dataKey != _LSP4_TOKEN_NAME_KEY);
        vm.assume(dataKey != _LSP4_TOKEN_SYMBOL_KEY);
        vm.assume(dataKey != _LSP4_TOKEN_TYPE_KEY);

        vm.prank(WARP_ROUTE_OWNER);
        syntheticToken.setData(dataKey, dataValue);

        vm.assertEq(syntheticToken.getData(dataKey), dataValue);
    }

    function test_OnlyOwnerCanSetDataKeys(
        address notOwnerAddress,
        bytes32[] memory dataKeys,
        bytes[] memory dataValues
    )
        public
    {
        vm.assume(notOwnerAddress != WARP_ROUTE_OWNER);
        bound(dataKeys.length, 1, 100);
        bound(dataValues.length, 1, 100);

        vm.prank(notOwnerAddress);
        vm.expectRevert("Ownable: caller is not the owner");
        syntheticToken.setDataBatch(dataKeys, dataValues);
    }

    function test_SetDataBatchRevertIfDataKeysAndValuesLengthMismatch(
        bytes32[] memory dataKeys,
        bytes[] memory dataValues
    )
        public
    {
        vm.assume(dataKeys.length != dataValues.length);

        vm.prank(WARP_ROUTE_OWNER);
        vm.expectRevert(ERC725Y_DataKeysValuesLengthMismatch.selector);
        syntheticToken.setDataBatch(dataKeys, dataValues);
    }

    function test_CanSetLSP4DataKeysToConfigureTokenInfosAndEmitRelevantDataChangedEvent() public {
        (bytes32[] memory dataKeys, bytes[] memory dataValues) = generateLSP4DataKeysAndValues();

        // CHECK events are emitted for the data keys:

        // - LSP4Creators[] (length)
        vm.expectEmit({ checkTopic1: true, checkTopic2: false, checkTopic3: false, checkData: true });
        emit IERC725Y.DataChanged(dataKeys[0], dataValues[0]);

        // - LSP4Creators[0] (index)
        vm.expectEmit({ checkTopic1: true, checkTopic2: false, checkTopic3: false, checkData: true });
        emit IERC725Y.DataChanged(dataKeys[1], dataValues[1]);

        // - LSP4CreatorMap
        vm.expectEmit({ checkTopic1: true, checkTopic2: false, checkTopic3: false, checkData: true });
        emit IERC725Y.DataChanged(dataKeys[2], dataValues[2]);

        // - LSP4Metadata
        vm.expectEmit({ checkTopic1: true, checkTopic2: false, checkTopic3: false, checkData: true });
        emit IERC725Y.DataChanged(dataKeys[3], dataValues[3]);

        vm.prank(WARP_ROUTE_OWNER);
        syntheticToken.setDataBatch(dataKeys, dataValues);

        // CHECK values for data keys have been set in the ERC725Y storage
        assertEq(syntheticToken.getDataBatch(dataKeys), dataValues);
    }
}
