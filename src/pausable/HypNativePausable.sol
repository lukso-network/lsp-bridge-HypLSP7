// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

// modules
import { HypNative } from "@hyperlane-xyz/core/contracts/token/HypNative.sol";
import { Freezable } from "./Freezable.sol";

contract HypNativePausable is HypNative, Freezable {
    constructor(address _mailbox) HypNative(_mailbox) { }

    function _transferRemote(
        uint32 _destination,
        bytes32 _recipient,
        uint256 _amountOrId,
        uint256 _value,
        bytes memory _hookMetadata,
        address _hook
    ) internal virtual override whenNotPaused() returns (bytes32 messageId) {
        return super._transferRemote(_destination, _recipient, _amountOrId, _value, _hookMetadata, _hook);
    }

    function _transferTo(
        address _recipient,
        uint256 _amount,
        bytes calldata  _metadata
    ) internal virtual override whenNotPaused() {
        HypNative._transferTo(_recipient, _amount, _metadata);
    }

}
