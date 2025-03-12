// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

/*
 __         __  __     __  __     ______     ______
/\ \       /\ \/\ \   /\ \/ /    /\  ___\   /\  __ \
\ \ \____  \ \ \_\ \  \ \  _"-.  \ \___  \  \ \ \/\ \
 \ \_____\  \ \_____\  \ \_\ \_\  \/\_____\  \ \_____\
  \/_____/   \/_____/   \/_/\/_/   \/_____/   \/_____/
*/

// ============ External Imports ============
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { IInterchainSecurityModule } from "@hyperlane-xyz/core/contracts/interfaces/IInterchainSecurityModule.sol";
// ============ Internal Imports ============
import { CircuitBreakerAdapter } from "./CircuitBreakerAdapter.sol";

/**
 * @title PausableISM
 * @dev A post-dispatch ISM based on Hyperlane to enable pausing a warp route on the destination chain.
 * The pausing functionality can be triggered by:
 * - an address with the `CIRCUIT_BREAKER_ROLE`
 * - or the owner of this contract.
 */
contract PausableIsm is IInterchainSecurityModule, Pausable, CircuitBreakerAdapter {
    uint8 public constant override moduleType = uint8(Types.NULL);

    constructor(address owner) CircuitBreakerAdapter(owner) { }

    /**
     * @inheritdoc IInterchainSecurityModule
     * @dev Reverts when paused, otherwise returns `true`.
     */
    function verify(bytes calldata, bytes calldata) external view whenNotPaused returns (bool) {
        return true;
    }

    function pause() external isCircuitBreakerOrOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
