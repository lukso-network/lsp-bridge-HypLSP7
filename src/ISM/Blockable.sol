// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

import { CircuitBreakerAdapter } from "./CircuitBreakerAdapter.sol";

event BlockedAddress(address _blockedAddress);

abstract contract Blockable is CircuitBreakerAdapter {
    mapping(address => bool) internal blocked_addresses;

    constructor(address owner) CircuitBreakerAdapter() {
        _transferOwnership(owner);
    }

    function blockAddress(address _address) external isCircuitBreakerOrOwner {
        blocked_addresses[_address] = true;
        emit BlockedAddress(_address);
    }
}
