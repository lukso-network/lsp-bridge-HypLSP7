// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/*@@@@@@@       @@@@@@@@@
 @@@@@@@@@       @@@@@@@@@
  @@@@@@@@@       @@@@@@@@@
   @@@@@@@@@       @@@@@@@@@
    @@@@@@@@@@@@@@@@@@@@@@@@@
     @@@@@  HYPERLANE  @@@@@@@
    @@@@@@@@@@@@@@@@@@@@@@@@@
   @@@@@@@@@       @@@@@@@@@
  @@@@@@@@@       @@@@@@@@@
 @@@@@@@@@       @@@@@@@@@
@@@@@@@@@       @@@@@@@@*/

import { IPostDispatchHook } from "@hyperlane-xyz/core/contracts/interfaces/hooks/IPostDispatchHook.sol";
import { AbstractPostDispatchHook } from "@hyperlane-xyz/core/contracts/hooks/libs/AbstractPostDispatchHook.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";

import { CircuitBreakerAdapter } from "./CircuitBreakerAdapter.sol";

contract PausableHook is AbstractPostDispatchHook, Pausable, CircuitBreakerAdapter {
    constructor(address owner) CircuitBreakerAdapter() Pausable() {
        _transferOwnership(owner);
    }

    // ============ External functions ============

    function pause() external isCircuitBreakerOrOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ External Functions ============

    /// @inheritdoc IPostDispatchHook
    function hookType() external pure override returns (uint8) {
        return uint8(IPostDispatchHook.Types.PAUSABLE);
    }

    // ============ Internal functions ============

    /// @inheritdoc AbstractPostDispatchHook
    function _postDispatch(bytes calldata metadata, bytes calldata message) internal override whenNotPaused { }

    /// @inheritdoc AbstractPostDispatchHook
    function _quoteDispatch(bytes calldata, bytes calldata) internal pure override returns (uint256) {
        return 0;
    }
}
