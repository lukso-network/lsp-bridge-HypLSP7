// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

// modules
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { LSP7DigitalAssetInitAbstract } from "@lukso/lsp7-contracts/contracts/LSP7DigitalAssetInitAbstract.sol";
import { CircuitBreaker } from "./CircuitBreaker.sol";
import { HypLSP7 } from "../HypLSP7.sol";

/**
 * @title LSP7 version of the Hyperlane ERC20 Token Router with Pausable feature
 * @dev See the `CircuitBreaker` contract for more infos on pausing
 */
contract HypLSP7Pausable is HypLSP7, CircuitBreaker {
    constructor(uint8 __decimals, address _mailbox) HypLSP7(__decimals, _mailbox) { }

    // overriden functions

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlUpgradeable, LSP7DigitalAssetInitAbstract)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
