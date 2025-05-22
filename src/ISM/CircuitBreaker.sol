// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;
/*
 __         __  __     __  __     ______     ______
/\ \       /\ \/\ \   /\ \/ /    /\  ___\   /\  __ \
\ \ \____  \ \ \_\ \  \ \  _"-.  \ \___  \  \ \ \/\ \
 \ \_____\  \ \_____\  \ \_\ \_\  \/\_____\  \ \_____\
  \/_____/   \/_____/   \/_/\/_/   \/_____/   \/_____/
*/
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";

event RegisteredCircuitBreaker(address indexed circuitBreaker);

event UnregisteredCircuitBreaker(address indexed circuitBreaker);

event CircuitBreakerTriggered();

event CircuitBreakerBypassed();

error NotCircuitBreakerOrOwner();

error CircuitError();

interface ICircuitBreakable {
    function circuitOpen() external view  returns (bool);
}

interface ICircuitBreaker {
    function paused() external view returns (bool);
}

bytes32 constant _HypLSP_CIRCUIT_BREAKER_KEY = 0x47ed5ddfcef19059e8642d926caadf37ff4ded3fa59cae8ed58d844bbeac9f4d;

contract CircuitBreaker is AccessControl, Ownable, Pausable {
    // The role given only to Circuit Breaker
    bytes32 public constant CIRCUIT_BREAKER_ROLE = keccak256("CIRCUIT_BREAKER_ROLE");

    constructor() Ownable() { }

    modifier isCircuitBreakerOrOwner() {
        if (!hasRole(CIRCUIT_BREAKER_ROLE, msg.sender) && msg.sender != owner()) {
            revert NotCircuitBreakerOrOwner();
        }
        _;
    }

    // Owner functions to add/remove Action Provider
    function registerCircuitBreaker(address _address) external onlyOwner {
        _grantRole(CIRCUIT_BREAKER_ROLE, _address);
        emit RegisteredCircuitBreaker(_address);
    }

    function unregisterCircuitBreaker(address _address) external onlyOwner {
        _revokeRole(CIRCUIT_BREAKER_ROLE, _address);
        emit UnregisteredCircuitBreaker( _address);
    }

    function pause() external isCircuitBreakerOrOwner {
        _pause();
        emit CircuitBreakerTriggered();
    }

    function unpause() external onlyOwner {
        _unpause();
        emit CircuitBreakerBypassed();
    }
}
