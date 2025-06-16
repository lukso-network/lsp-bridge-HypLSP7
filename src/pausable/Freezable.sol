// SPDX-License-Identifier: MIT OR Apache-2.0Add commentMore actions
pragma solidity >=0.8.0;

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

    // Owner functions to add/remove
    function changeFreezer(address newFreezer) external onlyOwner {
        if(frozenForever) revert FrozenForever();
        address previousFreezer = freezer;
        freezer = newFreezer;
        emit FreezerAddressChanged(previousFreezer, newFreezer);
    }

    function pause() external onlyFreezer {
        _pause();
    }

    function unpause() external onlyFreezer {
        _unpause();
    }

    function revokeFreezerForever() external onlyOwner {
        this.changeFreezer(address(0));
        frozenForever = true;
    }
}