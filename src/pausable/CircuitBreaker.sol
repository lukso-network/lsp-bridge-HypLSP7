// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

// modules
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

// events
event RegisteredCircuitBreaker(address ism, address circuitBreaker);

event UnregisteredCircuitBreaker(address ism, address circuitBreaker);

error NotCircuitBreakerOrOwner();

abstract contract CircuitBreaker is OwnableUpgradeable, AccessControlUpgradeable, PausableUpgradeable {
    /// Circuit Breaker role
    /// @dev Allows to trigger pausing (for instance for monitoring systems)
    bytes32 public constant CIRCUIT_BREAKER_ROLE = keccak256("CIRCUIT_BREAKER_ROLE");

    modifier isCircuitBreakerOrOwner() {
        if (!hasRole(CIRCUIT_BREAKER_ROLE, msg.sender) && msg.sender != owner()) {
            revert NotCircuitBreakerOrOwner();
        }
        _;
    }

    // TODO: the public functions `grantRole` from OpenZeppelin could do that and simplify.
    // However, there is also the role admin that complicates things a bit

    // Owner functions to add/remove Action Provider
    function registerCircuitBreaker(address _address) external onlyOwner {
        _grantRole(CIRCUIT_BREAKER_ROLE, _address);
        // TODO: these events can be removed for simplicity (use the `RoleGranted` event per warp route from
        // OpenZeppelin)
        emit RegisteredCircuitBreaker(address(this), _address);
    }

    function unregisterCircuitBreaker(address _address) external onlyOwner {
        _revokeRole(CIRCUIT_BREAKER_ROLE, _address);
        // TODO: these events can be removed for simplicity (use the `RoleGranted` event per warp route from
        // OpenZeppelin)
        emit UnregisteredCircuitBreaker(address(this), _address);
    }

    function pause() external isCircuitBreakerOrOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
