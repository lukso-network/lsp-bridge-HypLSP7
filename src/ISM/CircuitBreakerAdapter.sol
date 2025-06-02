// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

event RegisteredCircuitBreaker(address ism, address circuitBreaker);

event UnregisteredCircuitBreaker(address ism, address circuitBreaker);

error NotCircuitBreakerOrOwner();

abstract contract CircuitBreakerAdapter is AccessControlUpgradeable, OwnableUpgradeable, PausableUpgradeable {
    // The role given only to Circuit Breaker
    bytes32 public constant CIRCUIT_BREAKER_ROLE = keccak256("CIRCUIT_BREAKER_ROLE");

    constructor() { }

    modifier isCircuitBreakerOrOwner() {
        if (!hasRole(CIRCUIT_BREAKER_ROLE, msg.sender) && msg.sender != owner()) {
            revert NotCircuitBreakerOrOwner();
        }
        _;
    }

    // Owner functions to add/remove Action Provider
    function registerCircuitBreaker(address _address) external onlyOwner {
        _grantRole(CIRCUIT_BREAKER_ROLE, _address);
        emit RegisteredCircuitBreaker(address(this), _address);
    }

    function unregisterCircuitBreaker(address _address) external onlyOwner {
        _revokeRole(CIRCUIT_BREAKER_ROLE, _address);
        emit UnregisteredCircuitBreaker(address(this), _address);
    }

    function pause() external isCircuitBreakerOrOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
