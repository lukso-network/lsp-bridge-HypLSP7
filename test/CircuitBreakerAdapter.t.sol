// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.13;

import { Test } from "forge-std/src/Test.sol";

import {
    CircuitBreakerAdapter,
    RegisteredCircuitBreaker,
    UnregisteredCircuitBreaker,
    NotCircuitBreakerOrOwner
} from "../src/ISM/CircuitBreakerAdapter.sol";

contract Adapter is CircuitBreakerAdapter {
    constructor(address owner) CircuitBreakerAdapter(owner) { }

    uint256 public sensitiveCalls = 0;

    function somethingSensitive() external isCircuitBreakerOrOwner returns (bool) {
        sensitiveCalls++;
        return true;
    }
}

contract AdapterTest is Test {
    address internal ALICE = makeAddr("alice");
    address internal BOB = makeAddr("bob");
    address internal OWNER = makeAddr("owner");
    address internal CIRCUIT_BREAKER = makeAddr("circuit_breaker");

    Adapter adapter;

    function setUp() public {
        adapter = new Adapter(OWNER);
    }

    function testOwnerCanRegisterCircuitBreaker() public {
        vm.startPrank(OWNER);
        vm.expectEmit(true, false, false, false, address(adapter));
        emit RegisteredCircuitBreaker(address(this), address(adapter));
        adapter.registerCircuitBreaker(CIRCUIT_BREAKER);
        vm.stopPrank();
    }

    function testNonOwnersCannotRegisterCircuitBreaker() public {
        vm.prank(ALICE);
        vm.expectRevert("Ownable: caller is not the owner");
        adapter.registerCircuitBreaker(BOB);
    }

    function testOwnerCanUnregisterCircuitBreaker() public {
        vm.startPrank(OWNER);
        vm.expectEmit(true, false, false, false, address(adapter));
        emit UnregisteredCircuitBreaker(address(this), address(adapter));
        adapter.unregisterCircuitBreaker(CIRCUIT_BREAKER);
        vm.stopPrank();
    }

    function testNonOwnersCannotUnregisterCircuitBreaker() public {
        vm.prank(ALICE);
        vm.expectRevert("Ownable: caller is not the owner");
        adapter.unregisterCircuitBreaker(BOB);
    }

    function testCircuitBreakerCanCallSensitiveFunction() public {
        vm.prank(OWNER);
        adapter.registerCircuitBreaker(CIRCUIT_BREAKER);

        uint256 calls = adapter.sensitiveCalls();
        vm.prank(CIRCUIT_BREAKER);
        bool called = adapter.somethingSensitive();
        assertEq(called, true);

        uint256 calls2 = adapter.sensitiveCalls();
        assertEq(calls2, calls + 1);
    }

    function testNonCircuitBreakerCanNotCallSensitiveFunction() public {
        vm.prank(OWNER);
        adapter.registerCircuitBreaker(CIRCUIT_BREAKER);

        uint256 calls = adapter.sensitiveCalls();
        vm.prank(ALICE);
        vm.expectRevert(NotCircuitBreakerOrOwner.selector);
        bool called = adapter.somethingSensitive();
        assertEq(called, false);

        uint256 calls2 = adapter.sensitiveCalls();
        assertEq(calls2, calls);
    }

    function testOwnerCircuitBreakerCanCallSensitiveFunction() public {
        uint256 calls = adapter.sensitiveCalls();
        vm.prank(OWNER);
        bool called = adapter.somethingSensitive();
        assertEq(called, true);

        uint256 calls2 = adapter.sensitiveCalls();
        assertEq(calls2, calls + 1);
    }
}
