// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { LSP7DigitalAsset } from "@lukso/lsp7-contracts/contracts/LSP7DigitalAsset.sol";

contract LSP7Mock is LSP7DigitalAsset {
    constructor(
        string memory name_,
        string memory symbol_,
        address initialAccount_,
        uint256 initialBalance_
    )
        LSP7DigitalAsset(name_, symbol_, initialAccount_, 0, false)
    {
        _mint(initialAccount_, initialBalance_, true, "");
    }

    function mint(uint256 amount) public {
        _mint(msg.sender, amount, true, "");
    }

    function mintTo(address account, uint256 amount) public {
        _mint(account, amount, true, "");
    }

    function burnFrom(address account, uint256 amount) public {
        _burn(account, amount, "");
    }
}
