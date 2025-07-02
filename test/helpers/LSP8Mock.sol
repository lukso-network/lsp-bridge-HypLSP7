// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.13;

import { LSP8IdentifiableDigitalAsset } from "@lukso/lsp8-contracts/contracts/LSP8IdentifiableDigitalAsset.sol";

contract LSP8Mock is LSP8IdentifiableDigitalAsset {
    constructor(
        string memory name_,
        string memory symbol_,
        address owner_
    )
        LSP8IdentifiableDigitalAsset(name_, symbol_, owner_, 0, 0)
    { }

    function mint(address to, bytes32 tokenId, bool force, bytes memory data) public {
        _mint(to, tokenId, force, data);
    }

    function mintBatch(
        address[] memory to,
        bytes32[] memory tokenIds,
        bool[] memory force,
        bytes[] memory data
    )
        public
    {
        // solhint-disable-next-line gas-custom-errors
        require(
            to.length == tokenIds.length && tokenIds.length == force.length && force.length == data.length,
            "LSP8Mock: array length mismatch"
        );

        for (uint256 i = 0; i < to.length; i++) {
            _mint(to[i], tokenIds[i], force[i], data[i]);
        }
    }

    function mintIdRange(address to, uint256 startId, uint256 amount, bool force, bytes memory data) public {
        for (uint256 i = 0; i < amount; i++) {
            bytes32 tokenId = bytes32(startId + i);
            _mint(to, tokenId, force, data);
        }
    }

    function burn(bytes32 tokenId, bytes memory data) public {
        _burn(tokenId, data);
    }

    function burnBatch(bytes32[] memory tokenIds, bytes[] memory data) public {
        // solhint-disable-next-line gas-custom-errors
        require(tokenIds.length == data.length, "LSP8Mock: array length mismatch");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            _burn(tokenIds[i], data[i]);
        }
    }

    function setData(bytes32, /* tokenId */ bytes32 dataKey, bytes memory dataValue) public {
        _setData(dataKey, dataValue);
    }

    // Override for testing purposes - allows easy token ID verification
    function tokenURI(bytes32 /* tokenId */ ) public pure returns (string memory) {
        return "TEST-BASE-URI";
    }

    // Helper function for testing
    function exists(bytes32 tokenId) public view returns (bool) {
        return _exists(tokenId);
    }
}
