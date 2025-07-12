// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Test } from "forge-std/src/Test.sol";

import { Freezable } from "../../src/pausable/Freezable.sol";

abstract contract FreezableTester is Test {
    address internal immutable FREEZER = makeAddr("freezer");

    Freezable internal originPausableTokenRouter;
    Freezable internal destinationPausableTokenRouter;

    function _pauseOrigin() internal {
        if (!originPausableTokenRouter.paused()) {
            vm.prank(FREEZER);
            originPausableTokenRouter.pause();
        }
        assertEq(originPausableTokenRouter.paused(), true);
    }

    function _unpauseOrigin() internal {
        if (originPausableTokenRouter.paused()) {
            vm.prank(FREEZER);
            originPausableTokenRouter.unpause();
        }
        assertEq(originPausableTokenRouter.paused(), false);
    }

    function _pauseDestination() internal {
        if (!destinationPausableTokenRouter.paused()) {
            vm.prank(FREEZER);
            destinationPausableTokenRouter.pause();
        }
        assertEq(destinationPausableTokenRouter.paused(), true);
    }

    function _unpauseDestination() internal {
        if (destinationPausableTokenRouter.paused()) {
            vm.prank(FREEZER);
            destinationPausableTokenRouter.unpause();
        }
        assertEq(destinationPausableTokenRouter.paused(), false);
    }
}
