// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

// modules
import { LSP7DigitalAssetInitAbstract } from "@lukso/lsp7-contracts/contracts/LSP7DigitalAssetInitAbstract.sol";
import { Freezable } from "./Freezable.sol";
import { HypLSP7 } from "../HypLSP7.sol";

/**
 * @title LSP7 version of the Hyperlane ERC20 Token Router with Pausable feature
 * @dev See the `CircuitBreaker` contract for more infos on pausing
 */
contract HypLSP7Pausable is HypLSP7, Freezable {
    constructor(uint8 __decimals, address _mailbox) HypLSP7(__decimals, _mailbox) { }

    // overriden functions
    function _transferRemote(
        uint32 _destination,
        bytes32 _recipient,
        uint256 _amountOrId,
        uint256 _value,
        bytes memory _hookMetadata,
        address _hook
    )
        internal
        virtual
        override
        whenNotPaused
        returns (bytes32 messageId)
    {
        return super._transferRemote(_destination, _recipient, _amountOrId, _value, _hookMetadata, _hook);
    }

    function _transferTo(
        address _recipient,
        uint256 _amount,
        bytes calldata _metadata
    )
        internal
        virtual
        override
        whenNotPaused
    {
        HypLSP7._transferTo(_recipient, _amount, _metadata);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(LSP7DigitalAssetInitAbstract)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
