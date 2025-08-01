// SPDX-License-Identifier: MIT
pragma solidity >=0.8.22;

// modules
import { PausableController } from "./PausableController.sol";
import { HypLSP8 } from "../HypLSP8.sol";

/**
 * @title HypLSP8 with Pausable functionalities
 * @dev See the `PausableController` contract for more details
 */
contract HypLSP8Pausable is HypLSP8, PausableController {
    constructor(address _mailbox) HypLSP8(_mailbox) { }

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
        super._transferTo(_recipient, _amount, _metadata);
    }
}
