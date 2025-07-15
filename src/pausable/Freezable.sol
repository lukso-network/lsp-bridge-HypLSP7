// SPDX-License-Identifier: MIT
pragma solidity >=0.8.22;

// modules
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

// events
event FreezerAddressChanged(address previousFreezer, address newFreezer);

error NotFreezer(address caller);
error FrozenForever();

abstract contract Freezable is OwnableUpgradeable, PausableUpgradeable {
    address public freezer;
    bool public frozenForever;

    modifier onlyFreezer() {
        if (msg.sender != freezer) {
            revert NotFreezer(msg.sender);
        }
        _;
    }

    // Pausing functions

    function pause() external onlyFreezer {
        _pause();
    }

    function unpause() external onlyFreezer {
        _unpause();
    }

    // Configuration functions

    function changeFreezer(address newFreezer) public onlyOwner {
        _changeFreezer(newFreezer);
    }

    function revokeFreezerForever() public onlyOwner {
        _changeFreezer(address(0));
        frozenForever = true;
    }

    // Internal functions

    function _changeFreezer(address newFreezer) internal {
        if (frozenForever) revert FrozenForever();
        address previousFreezer = freezer;
        freezer = newFreezer;
        emit FreezerAddressChanged(previousFreezer, newFreezer);
    }
}
