// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Test } from "forge-std/src/Test.sol";

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {
    PausableController,
    CannotSetPausableControllerToZeroAddress,
    PausableControllerChanged
} from "../../contracts/pausable/PausableController.sol";

abstract contract PausableControllerTester is Test {
    address internal immutable PAUSABLE_CONTROLLER = makeAddr("Pausable controller");

    PausableController internal originPausableTokenRouter;
    PausableController internal destinationPausableTokenRouter;

    // Testing pausing features
    // --------------------

    function test_OwnerCanPauseAndUnpauseOnOrigin() public {
        address owner = originPausableTokenRouter.owner();

        assertFalse(originPausableTokenRouter.paused());

        // test pausing
        vm.prank(owner);
        vm.expectEmit({ emitter: address(originPausableTokenRouter) });
        emit PausableUpgradeable.Paused(owner);
        originPausableTokenRouter.pause();

        assertTrue(originPausableTokenRouter.paused());

        // test unpausing
        vm.prank(owner);
        vm.expectEmit({ emitter: address(originPausableTokenRouter) });
        emit PausableUpgradeable.Unpaused(owner);
        originPausableTokenRouter.unpause();

        assertFalse(originPausableTokenRouter.paused());
    }

    function test_PausableControllerCanPauseAndUnpauseOnOrigin() public {
        address pausableController = originPausableTokenRouter.pausableController();

        assertFalse(originPausableTokenRouter.paused());

        // test pausing
        vm.prank(pausableController);
        vm.expectEmit({ emitter: address(originPausableTokenRouter) });
        emit PausableUpgradeable.Paused(pausableController);
        originPausableTokenRouter.pause();

        assertTrue(originPausableTokenRouter.paused());

        // test unpausing
        vm.prank(pausableController);
        vm.expectEmit({ emitter: address(originPausableTokenRouter) });
        emit PausableUpgradeable.Unpaused(pausableController);
        originPausableTokenRouter.unpause();

        assertFalse(originPausableTokenRouter.paused());
    }

    function test_OwnerCanPauseAndUnpauseOnDestination() public {
        address owner = destinationPausableTokenRouter.owner();

        assertFalse(destinationPausableTokenRouter.paused());

        // test pausing
        vm.prank(owner);
        vm.expectEmit({ emitter: address(destinationPausableTokenRouter) });
        emit PausableUpgradeable.Paused(owner);
        destinationPausableTokenRouter.pause();

        assertTrue(destinationPausableTokenRouter.paused());

        // test unpausing
        vm.prank(owner);
        vm.expectEmit({ emitter: address(destinationPausableTokenRouter) });
        emit PausableUpgradeable.Unpaused(owner);
        destinationPausableTokenRouter.unpause();

        assertFalse(destinationPausableTokenRouter.paused());
    }

    function test_PausableControllerCanPauseOnDestination() public {
        address pausableController = destinationPausableTokenRouter.pausableController();

        assertFalse(destinationPausableTokenRouter.paused());

        // test pausing
        vm.prank(pausableController);
        vm.expectEmit({ emitter: address(destinationPausableTokenRouter) });
        emit PausableUpgradeable.Paused(pausableController);
        destinationPausableTokenRouter.pause();

        assertTrue(destinationPausableTokenRouter.paused());

        // test unpausing
        vm.prank(pausableController);
        vm.expectEmit({ emitter: address(destinationPausableTokenRouter) });
        emit PausableUpgradeable.Unpaused(pausableController);
        destinationPausableTokenRouter.unpause();

        assertFalse(destinationPausableTokenRouter.paused());
    }

    function test_OnlyOwnerCanChangePausableControllerOnOrigin(address caller, address input) public {
        // The derive tests use proxys and use this specific address as proxy admin. Omit it from fuzzing inputs
        address proxyAdmin = makeAddr("Proxy Admin");
        vm.assume(caller != originPausableTokenRouter.owner());
        vm.assume(caller != proxyAdmin);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        originPausableTokenRouter.changePausableController(input);
    }

    function test_OnlyOwnerCanChangePausableControllerOnDestination(address caller, address input) public {
        // The derive tests use proxys and use this specific address as proxy admin. Omit it from fuzzing inputs
        address proxyAdmin = makeAddr("Proxy Admin");
        vm.assume(caller != destinationPausableTokenRouter.owner());
        vm.assume(caller != proxyAdmin);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        destinationPausableTokenRouter.changePausableController(input);
    }

    function test_OwnerCannotSetPausableControllerToZeroAddressOnOrigin() public {
        address owner = originPausableTokenRouter.owner();

        vm.prank(owner);
        vm.expectRevert(CannotSetPausableControllerToZeroAddress.selector);
        originPausableTokenRouter.changePausableController(address(0));
    }

    function test_OwnerCannotSetPausableControllerToZeroAddressOnDestination() public {
        address owner = destinationPausableTokenRouter.owner();

        vm.prank(owner);
        vm.expectRevert(CannotSetPausableControllerToZeroAddress.selector);
        destinationPausableTokenRouter.changePausableController(address(0));
    }

    function test_OwnerCandisablePausingForeverOnOrigin() public {
        address owner = originPausableTokenRouter.owner();
        address pausableController = originPausableTokenRouter.pausableController();

        assertFalse(originPausableTokenRouter.disabledForever());

        vm.prank(owner);
        vm.expectEmit({ emitter: address(originPausableTokenRouter) });
        emit PausableControllerChanged(pausableController, address(0));
        originPausableTokenRouter.disablePausingForever();

        assertEq(originPausableTokenRouter.pausableController(), address(0));
        assertTrue(originPausableTokenRouter.disabledForever());
    }

    function test_OwnerCandisablePausingForeverOnDestination() public {
        address owner = destinationPausableTokenRouter.owner();
        address pausableController = destinationPausableTokenRouter.pausableController();

        assertFalse(originPausableTokenRouter.disabledForever());

        vm.prank(owner);
        vm.expectEmit({ emitter: address(destinationPausableTokenRouter) });
        emit PausableControllerChanged(pausableController, address(0));
        destinationPausableTokenRouter.disablePausingForever();

        assertEq(destinationPausableTokenRouter.pausableController(), address(0));
        assertTrue(destinationPausableTokenRouter.disabledForever());
    }

    function test_PausableControllerCanRevokeItselfForeverOnOrigin() public {
        address pausableController = originPausableTokenRouter.pausableController();

        assertFalse(originPausableTokenRouter.disabledForever());

        vm.prank(pausableController);
        vm.expectEmit({ emitter: address(originPausableTokenRouter) });
        emit PausableControllerChanged(pausableController, address(0));
        originPausableTokenRouter.disablePausingForever();

        assertEq(originPausableTokenRouter.pausableController(), address(0));
        assertTrue(originPausableTokenRouter.disabledForever());
    }

    function test_PausableControllerCanRevokeItselfForeverOnDestination() public {
        address pausableController = destinationPausableTokenRouter.pausableController();

        assertFalse(destinationPausableTokenRouter.disabledForever());

        vm.prank(pausableController);
        vm.expectEmit({ emitter: address(destinationPausableTokenRouter) });
        emit PausableControllerChanged(pausableController, address(0));
        destinationPausableTokenRouter.disablePausingForever();

        assertEq(destinationPausableTokenRouter.pausableController(), address(0));
        assertTrue(destinationPausableTokenRouter.disabledForever());
    }

    // Internal helper functions
    // --------------------

    function _pauseOrigin() internal {
        if (!originPausableTokenRouter.paused()) {
            vm.prank(PAUSABLE_CONTROLLER);
            originPausableTokenRouter.pause();
        }
        assertTrue(originPausableTokenRouter.paused());
    }

    function _unpauseOrigin() internal {
        if (originPausableTokenRouter.paused()) {
            vm.prank(PAUSABLE_CONTROLLER);
            originPausableTokenRouter.unpause();
        }
        assertFalse(originPausableTokenRouter.paused());
    }

    function _pauseDestination() internal {
        if (!destinationPausableTokenRouter.paused()) {
            vm.prank(PAUSABLE_CONTROLLER);
            destinationPausableTokenRouter.pause();
        }
        assertTrue(destinationPausableTokenRouter.paused());
    }

    function _unpauseDestination() internal {
        if (destinationPausableTokenRouter.paused()) {
            vm.prank(PAUSABLE_CONTROLLER);
            destinationPausableTokenRouter.unpause();
        }
        assertFalse(destinationPausableTokenRouter.paused());
    }
}
