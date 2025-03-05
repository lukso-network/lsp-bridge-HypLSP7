// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

event RegisteredCircuitBreaker(address ism, address circuitBreaker);

event UnregisteredCircuitBreaker(address ism, address circuitBreaker);

error NotCircuitBreakerOrOwner();

abstract contract CircuitBreakerAdapter is AccessControl, Ownable {
    // The role given only to Circuit Breaker
    bytes32 public constant CIRCUIT_BREAKER_ROLE = keccak256("CIRCUIT_BREAKER_ROLE");

    constructor(address owner) Ownable() {
        _transferOwnership(owner);
    }

    modifier isCircuitBreakerOrOwner() {
        if (!hasRole(CIRCUIT_BREAKER_ROLE, msg.sender)) {
            if (owner() != msg.sender) {
                revert NotCircuitBreakerOrOwner();
            }
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
}
