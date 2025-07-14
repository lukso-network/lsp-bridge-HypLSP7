// SPDX-License-Identifier: MIT
pragma solidity >=0.8.27;

// modules
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

// events
event PausableControllerChanged(address previousPausableController, address newPausableController);

// errors
error NotPausableControllerOrOwner(address caller);
error CannotSetPausableControllerToZeroAddress();
error CannotDisablePausingForeverWhenBridgePaused();
error PausingDisabled();

/**
 * @title PausableController
 * @dev Contract with pausing / unpausing functionalities configured as follow:
 * - owner + pausable controller can pause / unpause.
 * - allow the owner to revoke the pausable controller forever
 * Additional features include:
 * - ability for the owner to also pause
 *
 */
abstract contract PausableController is OwnableUpgradeable, PausableUpgradeable {
    address public pausableController;
    bool public disabledForever;

    modifier onlyOwnerOrPausableController() {
        require(msg.sender == pausableController || msg.sender == owner(), NotPausableControllerOrOwner(msg.sender));
        _;
    }

    // Pausing functions
    // --------------------

    function pause() external onlyOwnerOrPausableController {
        require(!disabledForever, PausingDisabled());
        _pause();
    }

    function unpause() external onlyOwnerOrPausableController {
        _unpause();
    }

    // Configuration functions
    // --------------------

    function changePausableController(address newPausableController) public onlyOwner {
        require(newPausableController != address(0), CannotSetPausableControllerToZeroAddress());
        _changePausableController(newPausableController);
    }

    function disablePausingForever() public onlyOwnerOrPausableController {
        require(!paused(), CannotDisablePausingForeverWhenBridgePaused());
        // check if not already disabled
        require(!disabledForever, PausingDisabled());
        _changePausableController(address(0));
        disabledForever = true;
    }

    // Internal functions
    // --------------------

    function _changePausableController(address newPausableController) internal {
        require(!disabledForever, PausingDisabled());

        address previousPausableController = pausableController;
        pausableController = newPausableController;

        emit PausableControllerChanged(previousPausableController, newPausableController);
    }
}
