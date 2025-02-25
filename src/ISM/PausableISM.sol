// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

// ============ External Imports ============
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { IInterchainSecurityModule } from "@hyperlane-xyz/core/contracts/interfaces/IInterchainSecurityModule.sol";
// ============ Internal Imports ============
import { CircuitBreakerAdapter } from "./CircuitBreakerAdapter.sol";

contract PausableIsm is IInterchainSecurityModule, Pausable, CircuitBreakerAdapter {
    uint8 public constant override moduleType = uint8(Types.NULL);

    constructor(address owner) CircuitBreakerAdapter() Pausable() {
        _transferOwnership(owner);
    }

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
