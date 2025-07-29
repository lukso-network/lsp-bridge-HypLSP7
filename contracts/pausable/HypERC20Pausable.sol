// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

// modules
import { HypERC20 } from "@hyperlane-xyz/core/contracts/token/HypERC20.sol";
import { PausableController } from "./PausableController.sol";

/**
 * @title Hyperlane ERC20 Token Router with Pausable functionalities
 * @dev See the `PausableController` contract for more details
 */
contract HypERC20Pausable is HypERC20, PausableController {
    constructor(uint8 __decimals, uint256 _scale, address _mailbox) HypERC20(__decimals, _scale, _mailbox) { }

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
