// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { LSP7DigitalAsset } from "@lukso/lsp7-contracts/contracts/LSP7DigitalAsset.sol";

import { _LSP4_TOKEN_TYPE_TOKEN } from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";

contract LSP7Mock is LSP7DigitalAsset {
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_,
        address tokenContractOwner_
    )
        LSP7DigitalAsset(name_, symbol_, tokenContractOwner_, _LSP4_TOKEN_TYPE_TOKEN, false)
    {
        // TODO: mint to deployer to unify code like ERC20Mock for simplicity
        _mint(tokenContractOwner_, totalSupply_, true, "");
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
