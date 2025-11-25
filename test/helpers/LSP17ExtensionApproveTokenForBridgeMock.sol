// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { LSP17Extension } from "@lukso/lsp17contractextension-contracts/contracts/LSP17Extension.sol";
import { ILSP7DigitalAsset as ILSP7 } from "@lukso/lsp7-contracts/contracts/ILSP7DigitalAsset.sol";

/// @dev Mock extension to register in an LSP7 token for the function selectors:
/// - `allowance(address,address)`
/// - `approve(address,uint256)`
///
/// This is used to test in an `HypLSP7Collateral` contract that calling `approveTokenForBridge(...)`
/// would call this contract via a registered LSP17 extension on the LSP7 token contract without reverting.
contract LSP17ExtensionApproveTokenForBridgeMock is LSP17Extension {
    ILSP7 public token;

    event ApprovedOnExtensionCalled();

    constructor(ILSP7 token_) {
        token = token_;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return token.authorizedAmountFor({ operator: spender, tokenOwner: owner });
    }

    function approve(
        address,
        /* spender */
        uint256 /* value */
    )
        external
        returns (bool)
    {
        emit ApprovedOnExtensionCalled();
        return true;
    }
}
