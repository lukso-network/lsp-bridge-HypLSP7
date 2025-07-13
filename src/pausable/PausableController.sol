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
error PausableControllerRevokedForever();

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
    bool public revokedForever;

    modifier onlyOwnerOrPausableController() {
        require(msg.sender == pausableController || msg.sender == owner(), NotPausableControllerOrOwner(msg.sender));
        _;
    }

    // Pausing functions
    // --------------------

    function pause() external onlyOwnerOrPausableController {
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

    function revokePausableControllerForever() public onlyOwnerOrPausableController {
        _changePausableController(address(0));
        revokedForever = true;
    }

    // Internal functions
    // --------------------

    function _changePausableController(address newPausableController) internal {
        require(!revokedForever, PausableControllerRevokedForever());

        address previousPausableController = pausableController;
        pausableController = newPausableController;

        emit PausableControllerChanged(previousPausableController, newPausableController);
    }
}
