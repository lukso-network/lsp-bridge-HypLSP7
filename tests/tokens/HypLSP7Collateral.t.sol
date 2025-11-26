// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { Test } from "forge-std/src/Test.sol";

// mock contracts
import { TestMailbox } from "@hyperlane-xyz/core/contracts/test/TestMailbox.sol";
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";
import { TestIsm } from "@hyperlane-xyz/core/contracts/test/TestIsm.sol";
import { ERC20Mock } from "../helpers/ERC20Mock.sol";
import { LSP7Mock } from "../helpers/LSP7Mock.sol";
import { LSP17ExtensionApproveTokenForBridgeMock } from "..//helpers/LSP17ExtensionApproveTokenForBridgeMock.sol";

// contracts to test
import { HypLSP7Collateral } from "../../contracts/HypLSP7Collateral.sol";
import { ValueTransferBridge } from "@hyperlane-xyz/core/contracts/token/interfaces/ValueTransferBridge.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

// utilities
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import { LSP2Utils } from "@lukso/lsp2-contracts/contracts/LSP2Utils.sol";

// constants
import { _LSP17_EXTENSION_PREFIX } from "@lukso/lsp17contractextension-contracts/contracts/LSP17Constants.sol";

// errors
import { NoExtensionFoundForFunctionSelector } from "@lukso/lsp17contractextension-contracts/contracts/LSP17Errors.sol";

contract HypLSP7CollateralTest is Test {
    using TypeCasts for address;

    // Token being bridged
    // In production, we assume it is an LSP7 token already deployed
    // (on LUKSO or any other EVM origin chain)
    // ---------------------------
    string internal constant NAME = "CHILL";
    string internal constant SYMBOL = "CHILL";
    uint8 internal constant DECIMALS = 18;
    uint256 internal constant TOTAL_SUPPLY = 1_000_000 * (10 ** DECIMALS);

    // Hyperlane Mailbox
    uint32 internal constant CHAIN_ID = 42;
    TestMailbox internal mailbox;

    // Warp route configs
    HypLSP7Collateral internal lsp7Collateral;
    TestPostDispatchHook internal defaultHook;
    TestIsm internal defaultIsm;

    address internal immutable PROXY_ADMIN = makeAddr("Proxy Admin");
    address internal immutable WARP_ROUTE_OWNER = makeAddr("warp route owner");

    // Scale outbount amounts down and inbound amounts up.
    // Used when different chains of the route have different decimals place to unify semantics of amounts in message.
    // Since we are bridging between two similar EVM chains, scaling is not required so we keep the parameter to 1.
    uint256 internal constant SCALE_PARAM = 1;

    // Token being bridged
    // In production, we assume it is an LSP7 token already deployed
    // (on LUKSO or any other EVM origin chain)
    // ---------------------------
    LSP7Mock internal token;

    function setUp() public {
        mailbox = new TestMailbox(CHAIN_ID);

        // Deploy the initial token that we will bridge from the origin chain
        token = new LSP7Mock(NAME, SYMBOL, TOTAL_SUPPLY, address(this));

        // Deploy collateral token router
        defaultHook = new TestPostDispatchHook();
        defaultIsm = new TestIsm();

        lsp7Collateral = new HypLSP7Collateral(address(token), SCALE_PARAM, address(mailbox));
        lsp7Collateral.initialize(address(defaultHook), address(defaultIsm), WARP_ROUTE_OWNER);
    }

    function test_DeployRevertWhenTokenAddressIsEOA(address eoa) public {
        vm.assume(eoa != address(0));
        vm.assume(eoa.code.length == 0);
        assumeNotPrecompile(eoa);

        vm.expectRevert("HypLSP7Collateral: invalid token");
        lsp7Collateral = new HypLSP7Collateral(address(eoa), SCALE_PARAM, address(mailbox));
    }

    function test_OwnerCanCallAuthorizeTokenForBridge() public {
        uint32 destinationChainId = 1; // Ethereum

        // Enroll remote router initially
        // token router on destination is placeholder as we are not doing any bridging
        vm.prank(WARP_ROUTE_OWNER);
        lsp7Collateral.enrollRemoteRouter(
            destinationChainId, 0x000000000000000000000000CAfEcAfeCAfECaFeCaFecaFecaFECafECafeCaFe
        );

        address allowedBridge = makeAddr("allowed bridge");

        // initial setup for rebalancing
        vm.prank(WARP_ROUTE_OWNER);
        lsp7Collateral.addBridge(destinationChainId, ValueTransferBridge(allowedBridge));

        // CHECK `bridge` is not an operator for collateral contract
        uint256 allowanceBefore =
            token.authorizedAmountFor({ operator: allowedBridge, tokenOwner: address(lsp7Collateral) });
        assertEq(allowanceBefore, 0);

        // Allow bridge to move funds from collateral
        vm.prank(WARP_ROUTE_OWNER);
        lsp7Collateral.authorizeTokenForBridge(token, ValueTransferBridge(allowedBridge));

        // CHECK `bridge` is now an operator for collateral contract
        uint256 allowanceAfter =
            token.authorizedAmountFor({ operator: allowedBridge, tokenOwner: address(lsp7Collateral) });
        assertEq(allowanceAfter, type(uint256).max);
    }

    function test_FuzzOwnerCanCallAuthorizeTokenForBridge(uint32 destinationChainId, address allowedBridge) public {
        vm.assume(destinationChainId != CHAIN_ID);
        vm.assume(allowedBridge != address(0));
        assumeNotPrecompile(allowedBridge);
        // prevent setting the `allowedBridge` operator to be the collateral contract itself,
        // which will revert with `LSP7TokenOwnerCannotBeOperator()`
        vm.assume(allowedBridge != address(lsp7Collateral));

        // Enroll remote router initially
        // token router on destination is placeholder as we are not doing any bridging
        vm.prank(WARP_ROUTE_OWNER);
        lsp7Collateral.enrollRemoteRouter(
            destinationChainId, 0x000000000000000000000000CAfEcAfeCAfECaFeCaFecaFecaFECafECafeCaFe
        );

        // initial setup for rebalancing
        vm.prank(WARP_ROUTE_OWNER);
        lsp7Collateral.addBridge(destinationChainId, ValueTransferBridge(allowedBridge));

        // CHECK `bridge` is not an operator for collateral contract
        uint256 allowanceBefore =
            token.authorizedAmountFor({ operator: allowedBridge, tokenOwner: address(lsp7Collateral) });
        assertEq(allowanceBefore, 0);

        // Allow bridge to move funds from collateral
        vm.prank(WARP_ROUTE_OWNER);
        lsp7Collateral.authorizeTokenForBridge(token, ValueTransferBridge(allowedBridge));

        // CHECK `bridge` is now an operator for collateral contract
        uint256 allowanceAfter =
            token.authorizedAmountFor({ operator: allowedBridge, tokenOwner: address(lsp7Collateral) });
        assertEq(allowanceAfter, type(uint256).max);
    }

    function test_OnlyOwnerCanAuthorizeTokenForBridge(address caller) public {
        vm.assume(caller != PROXY_ADMIN);
        vm.assume(caller != WARP_ROUTE_OWNER);

        uint32 destinationChainId = 1; // Ethereum

        // Enroll remote router initially
        // token router on destination is placeholder as we are not doing any bridging
        vm.prank(WARP_ROUTE_OWNER);
        lsp7Collateral.enrollRemoteRouter(
            destinationChainId, 0x000000000000000000000000CAfEcAfeCAfECaFeCaFecaFecaFECafECafeCaFe
        );

        address allowedBridge = makeAddr("allowed bridge");

        // initial setup for rebalancing
        vm.prank(WARP_ROUTE_OWNER);
        lsp7Collateral.addBridge(destinationChainId, ValueTransferBridge(allowedBridge));

        // CHECK `bridge` is not an operator for collateral contract
        uint256 allowanceBefore =
            token.authorizedAmountFor({ operator: allowedBridge, tokenOwner: address(lsp7Collateral) });
        assertEq(allowanceBefore, 0);

        // Allow bridge to move funds from collateral
        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        lsp7Collateral.authorizeTokenForBridge(token, ValueTransferBridge(allowedBridge));

        assertEq(
            token.authorizedAmountFor({ operator: allowedBridge, tokenOwner: address(lsp7Collateral) }), allowanceBefore
        );
    }

    /// @dev Test that `approveTokenForBridge(...)` function will revert and is not usable
    function test_FuzzApproveTokenForBridgeCanBeCalledButRevertsAndIsUnusable(
        uint32 destinationChainId,
        address allowedBridge
    )
        public
    {
        vm.assume(destinationChainId != CHAIN_ID);
        vm.assume(allowedBridge != address(0));
        assumeNotPrecompile(allowedBridge);

        // Enroll remote router initially
        // token router on destination is placeholder as we are not doing any bridging
        vm.prank(WARP_ROUTE_OWNER);
        lsp7Collateral.enrollRemoteRouter(
            destinationChainId, 0x000000000000000000000000CAfEcAfeCAfECaFeCaFecaFecaFECafECafeCaFe
        );

        // initial setup for rebalancing
        vm.prank(WARP_ROUTE_OWNER);
        lsp7Collateral.addBridge(destinationChainId, ValueTransferBridge(allowedBridge));

        // CHECK `bridge` is not an operator for collateral contract
        uint256 allowanceBefore =
            token.authorizedAmountFor({ operator: allowedBridge, tokenOwner: address(lsp7Collateral) });
        assertEq(allowanceBefore, 0);

        vm.prank(WARP_ROUTE_OWNER);
        vm.expectRevert({
            // `approveTokenForBridge(...)` uses `SafeERC20.safeApprove(...)` library function, which does the following
            // calls:
            // - `allowance(address,address)` = `0xdd62ed3e`
            // - `approve(address,uint256)` = `0x095ea7b3`
            //
            // the call to `allowance(...)` will revert first
            revertData: abi.encodeWithSelector(NoExtensionFoundForFunctionSelector.selector, IERC20.allowance.selector),
            reverter: address(token)
        });
        lsp7Collateral.approveTokenForBridge(
            IERC20(address(token)), // forcing type casting to check revert behaviour
            ValueTransferBridge(allowedBridge)
        );

        // CHECK `bridge` is still not an operator for tokens locked in the collateral contract, and no allowance has
        // been given
        uint256 allowanceAfter =
            token.authorizedAmountFor({ operator: allowedBridge, tokenOwner: address(lsp7Collateral) });
        assertEq(allowanceAfter, allowanceBefore);
    }

    /// @dev Test that it does not revert if an LSP17Extension contract is registered on the LSP7 token for function
    /// selectors:
    // - `allowance(address,address)` = `0xdd62ed3e`
    // - `approve(address,uint256)` = `0x095ea7b3`
    function test_FuzzApproveTokenForBridgeCanBeCalledAndNotRevertIfExtensionsRegistered(
        uint32 destinationChainId,
        address allowedBridge
    )
        public
    {
        vm.assume(destinationChainId != CHAIN_ID);
        vm.assume(allowedBridge != address(0));
        assumeNotPrecompile(allowedBridge);

        // Deploy extension contract
        address lsp17extension = address(new LSP17ExtensionApproveTokenForBridgeMock(token));

        // LSP17Extension:`allowance(address,address)`
        bytes32 lsp17DataKeyForAllowance =
            LSP2Utils.generateMappingKey(_LSP17_EXTENSION_PREFIX, IERC20.allowance.selector);

        // LSP17Extension:`approve(address,uint256)`
        bytes32 lsp17DataKeyForApprove = LSP2Utils.generateMappingKey(_LSP17_EXTENSION_PREFIX, IERC20.approve.selector);

        // register LSP17Extension contract in the LSP7 token for each selectors
        token.setData(lsp17DataKeyForAllowance, abi.encodePacked(lsp17extension));
        token.setData(lsp17DataKeyForApprove, abi.encodePacked(lsp17extension));

        // Sanity check to ensure the call to the newly registered selectors work

        // Doing `token.allowance(...)` should return the same result as doing `token.authorizedAmountFor(...)`
        // We force casting to ERC20 interface for simplicity to make view calls over crafting low level calls
        assertEq(
            IERC20(address(token)).allowance(address(lsp7Collateral), allowedBridge),
            token.authorizedAmountFor(allowedBridge, address(lsp7Collateral))
        );

        // approve function does not do anything
        vm.expectEmit({ emitter: lsp17extension });
        emit LSP17ExtensionApproveTokenForBridgeMock.ApprovedOnExtensionCalled();
        IERC20(address(token)).approve(address(123), 456);

        // ERC20 functions return true on success
        //
        // ```
        // function approve(address spender, uint256 value) external returns (bool);
        // ```
        assertTrue(IERC20(address(token)).approve(address(123), 456));

        // Enroll remote router initially
        // token router on destination is placeholder as we are not doing any bridging
        vm.prank(WARP_ROUTE_OWNER);
        lsp7Collateral.enrollRemoteRouter(
            destinationChainId, 0x000000000000000000000000CAfEcAfeCAfECaFeCaFecaFecaFECafECafeCaFe
        );

        // initial setup for rebalancing
        vm.prank(WARP_ROUTE_OWNER);
        lsp7Collateral.addBridge(destinationChainId, ValueTransferBridge(allowedBridge));

        vm.prank(WARP_ROUTE_OWNER);
        vm.expectEmit({ emitter: lsp17extension });
        emit LSP17ExtensionApproveTokenForBridgeMock.ApprovedOnExtensionCalled();
        lsp7Collateral.approveTokenForBridge(
            IERC20(address(token)), // forcing type casting to check revert behaviour
            ValueTransferBridge(allowedBridge)
        );
    }

    function test_DeployAndLinkToERC20TokenTransferRemoteFails() public {
        ERC20Mock erc20Token = new ERC20Mock("Test Token", "TT", 1_000_000 * (10 ** 18), 18);
        lsp7Collateral = new HypLSP7Collateral(address(erc20Token), SCALE_PARAM, address(mailbox));

        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        uint256 transferAmount = 10 ether;

        vm.deal(alice, 20 ether);

        vm.prank(alice);
        // since ERC20 does not have a fallback function, it will be a silent revert (no revert reason)
        vm.expectRevert(bytes(""));
        lsp7Collateral.transferRemote{ value: 1 ether }(1, bob.addressToBytes32(), transferAmount);
    }
}
