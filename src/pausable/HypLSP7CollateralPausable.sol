// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

// modules
import { CircuitBreaker } from "./CircuitBreaker.sol";
import { HypLSP7Collateral } from "../HypLSP7Collateral.sol";

contract HypLSP7CollateralPausable is HypLSP7Collateral, CircuitBreaker {
    constructor(address lsp7_, address mailbox_) HypLSP7Collateral(lsp7_, mailbox_) { }
}
