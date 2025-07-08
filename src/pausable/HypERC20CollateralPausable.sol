// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

// modules
import { HypERC20Collateral } from "@hyperlane-xyz/core/contracts/token/HypERC20Collateral.sol";
import { Freezable } from "./Freezable.sol";

/**
 * @title Hyperlane ERC20Collateral Token Router with Pausable functionalities
 * @dev See the `Freezable` contract for more details
 */
contract HypERC20CollateralPausable is HypERC20Collateral, Freezable {
    constructor(address erc20_, uint256 scale_, address mailbox_) HypERC20Collateral(erc20_, scale_, mailbox_) { }

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
