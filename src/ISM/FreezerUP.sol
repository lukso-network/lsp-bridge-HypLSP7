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

error FrozenError();

interface IFreezeable {
    function frozen() external view  returns (bool);
}

interface IFreezer {
    function paused() external view returns (bool);
}

contract FreezerUP is AccessControl, Ownable, Pausable {
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
