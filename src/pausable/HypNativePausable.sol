// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

// modules
import { HypNative } from "@hyperlane-xyz/core/contracts/token/HypNative.sol";
import { Freezable } from "./Freezable.sol";

/**
 * @title Hyperlane Native Token Router with Pausable functionalities
 * @dev See the `Freezable` contract for more details
 */
contract HypNativePausable is HypNative, Freezable {
    /**
     * @param _scale A parameter used for native tokens that use different number of decimals than 1e18 (e.g: Solana
     * Sealevel with 1e9 for 9 decimals)
     * @param _mailbox The mailbox configured with this warp route
     */
    constructor(uint256 _scale, address _mailbox) HypNative(_scale, _mailbox) { }

    function _transferRemote(
        uint32 _destination,
        bytes32 _recipient,
        uint256 _amount,
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
        return super._transferRemote(_destination, _recipient, _amount, _value, _hookMetadata, _hook);
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
