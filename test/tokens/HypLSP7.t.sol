// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Test } from "forge-std/src/Test.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { TestMailbox } from "@hyperlane-xyz/core/contracts/test/TestMailbox.sol";
import { TestPostDispatchHook } from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";
import { TestIsm } from "@hyperlane-xyz/core/contracts/test/TestIsm.sol";
import { HypLSP7 } from "../../src/HypLSP7.sol";

contract HypLSP7Test is Test {
    // Hyperlane Mailbox
    uint32 constant CHAIN_ID = 42;
    TestMailbox mailbox;

    // Warp route
    TestPostDispatchHook internal defaultHook;
    TestIsm internal defaultIsm;

    string internal constant NAME = "Test USDC";
    string internal constant SYMBOL = "tUSDC";
    uint8 internal constant DECIMALS = 6; // USDC has 6 decimals points
    uint256 internal constant TOTAL_SUPPLY = 1_000_000 * (10 ** DECIMALS);

    uint256 internal constant SCALE_PARAM = 1;

    address internal immutable PROXY_ADMIN = makeAddr("Proxy Admin");
    address internal immutable WARP_ROUTE_OWNER = makeAddr("warp route owner");

    HypLSP7 syntheticToken;

    function setUp() public {
        mailbox = new TestMailbox(CHAIN_ID);

        defaultHook = new TestPostDispatchHook();
        defaultIsm = new TestIsm();

        HypLSP7 implementation = new HypLSP7(DECIMALS, SCALE_PARAM, address(mailbox));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            PROXY_ADMIN,
            abi.encodeCall(
                HypLSP7.initialize,
                (TOTAL_SUPPLY, NAME, SYMBOL, address(defaultHook), address(defaultIsm), WARP_ROUTE_OWNER)
            )
        );

        syntheticToken = HypLSP7(payable(proxy));
    }
}
