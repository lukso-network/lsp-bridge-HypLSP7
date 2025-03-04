// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

// ============= EXTERNAL ==============================
import { IPostDispatchHook } from "@hyperlane-xyz/core/contracts/interfaces/hooks/IPostDispatchHook.sol";
import { AbstractPostDispatchHook } from "@hyperlane-xyz/core/contracts/hooks/libs/AbstractPostDispatchHook.sol";

// ============= INTERNAL ==============================
import { Blockable } from "./Blockable.sol";

contract BadAddyHook is AbstractPostDispatchHook, Blockable {
    constructor(address owner) Blockable(owner) { }

    /// @inheritdoc IPostDispatchHook
    function hookType() external pure override returns (uint8) {
        return uint8(IPostDispatchHook.Types.PAUSABLE);
    }

    // ============ Internal functions ============

    /// @inheritdoc AbstractPostDispatchHook
    function _postDispatch(bytes calldata, bytes calldata) internal override {
        // Blocking from `tx.origin` because metadata containing sender
        // or TokenMessage/TokenMessageForLSP containing sender is unreliable AND/OR spoofable
        if (blocked_addresses[tx.origin]) {
            revert("!blocked");
        }
    }

    /// @inheritdoc AbstractPostDispatchHook
    function _quoteDispatch(bytes calldata, bytes calldata) internal pure override returns (uint256) {
        return 0;
    }
}
