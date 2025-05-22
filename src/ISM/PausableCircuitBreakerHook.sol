// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/*
 __         __  __     __  __     ______     ______
/\ \       /\ \/\ \   /\ \/ /    /\  ___\   /\  __ \
\ \ \____  \ \ \_\ \  \ \  _"-.  \ \___  \  \ \ \/\ \
 \ \_____\  \ \_____\  \ \_\ \_\  \/\_____\  \ \_____\
  \/_____/   \/_____/   \/_/\/_/   \/_____/   \/_____/
*/

import { IPostDispatchHook } from "@hyperlane-xyz/core/contracts/interfaces/hooks/IPostDispatchHook.sol";
import { AbstractPostDispatchHook } from "@hyperlane-xyz/core/contracts/hooks/libs/AbstractPostDispatchHook.sol";

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import { CircuitBreakerAdapter } from "./CircuitBreakerAdapter.sol";

/**
 * @title PausableCircuitBreakerHook
 * @dev A post-dispatch hook based on Hyperlane to enable pausing a warp route on the origin chain.
 *
 * The pausing functionality can be triggered by:
 * - an address with the `CIRCUIT_BREAKER_ROLE`
 * - or the owner of this contract.
 *
 * Unpausing can be triggered only by the owner of this contract.
 */
contract PausableCircuitBreakerHook is AbstractPostDispatchHook, PausableUpgradeable, CircuitBreakerAdapter {
    constructor(address owner) CircuitBreakerAdapter() { }

    // function pause() external isCircuitBreakerOrOwner {
    //     _pause();
    // }

    // function unpause() external onlyOwner {
    //     _unpause();
    // }

    // ============ External Functions ============

    /// @inheritdoc IPostDispatchHook
    function hookType() external pure override returns (uint8) {
        return uint8(IPostDispatchHook.Types.PAUSABLE);
    }

    /// @inheritdoc AbstractPostDispatchHook
    /// @dev Do not run any logic post dispatch in this
    function _postDispatch(bytes calldata metadata, bytes calldata message) internal override whenNotPaused { }

    /// @inheritdoc AbstractPostDispatchHook
    function _quoteDispatch(bytes calldata, bytes calldata) internal pure override returns (uint256) {
        return 0;
    }
}
