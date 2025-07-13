// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Message } from "@hyperlane-xyz/core/contracts/libs/Message.sol";

import { IPostDispatchHook } from "@hyperlane-xyz/core/contracts/interfaces/hooks/IPostDispatchHook.sol";
import { AbstractPostDispatchHook } from "@hyperlane-xyz/core/contracts/hooks/libs/AbstractPostDispatchHook.sol";

/**
 * @title Custom Post Dispatch Hook with specific event emitted
 * @dev Same as `@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol` + custom event emitted inside
 * `_postDispatch(...)`.
 * Used for testing purpose to test the custom event is emitted.
 */
contract CustomPostDispatchHook is AbstractPostDispatchHook {
    using Message for bytes;

    // ============ Custom Event ============
    event CustomPostDispatchHookCalled(bytes hookMetadata);

    // ============ Public Storage ============

    // test fees for quoteDispatch
    uint256 public fee = 0;

    // used to keep track of dispatched message
    mapping(bytes32 messageId => bool dispatched) public messageDispatched;

    // ============ External Functions ============

    /// @inheritdoc IPostDispatchHook
    function hookType() external pure override returns (uint8) {
        return uint8(IPostDispatchHook.Types.UNUSED);
    }

    function supportsMetadata(bytes calldata) public pure override returns (bool) {
        return true;
    }

    function setFee(uint256 _fee) external {
        fee = _fee;
    }

    // ============ Internal functions ============
    function _postDispatch(bytes calldata metadata, bytes calldata message) internal override {
        messageDispatched[message.id()] = true;
        emit CustomPostDispatchHookCalled(metadata);
    }

    function _quoteDispatch(
        bytes calldata, /*metadata*/
        bytes calldata /*message*/
    )
        internal
        view
        override
        returns (uint256)
    {
        return fee;
    }
}
