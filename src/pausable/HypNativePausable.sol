// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

// modules
import { HypNative } from "@hyperlane-xyz/core/contracts/token/HypNative.sol";
import { CircuitBreaker } from "./CircuitBreaker.sol";

contract HypNativePausable is HypNative, CircuitBreaker {
    constructor(address _mailbox) HypNative(_mailbox) { }
}
