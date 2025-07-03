// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

// modules
import { Freezable } from "./Freezable.sol";
import { HypLSP7Collateral } from "../HypLSP7Collateral.sol";

/**
 * @title HypLSP7Collateral with Pausable functionalities
 * @dev See the `Freezable` contract for more details
 */
contract HypLSP7CollateralPausable is HypLSP7Collateral, Freezable {
    constructor(address lsp7_, uint256 _scale, address mailbox_) HypLSP7Collateral(lsp7_, _scale, mailbox_) { }

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
        super._transferTo(_recipient, _amount, _metadata);
    }
}
