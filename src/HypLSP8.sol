// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.19;

import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";

import { ILSP8IdentifiableDigitalAsset } from "@lukso/lsp8-contracts/contracts/ILSP8IdentifiableDigitalAsset.sol";

import {LSP8IdentifiableDigitalAssetInitAbstract} from "@lukso/lsp8-contracts/contracts/LSP8IdentifiableDigitalAssetInitAbstract.sol";

import { _LSP4_TOKEN_TYPE_TOKEN } from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";

import { _LSP8_TOKENID_FORMAT_NUMBER } from "@lukso/lsp8-contracts/contracts/LSP8Constants.sol";



/**
 * @title Hyperlane LSP8 Token Router that extends LSP8 with remote transfer functionality.
 * @author Abacus Works
 */
contract HypLSP8 is LSP8IdentifiableDigitalAssetInitAbstract, TokenRouter {
    constructor(address _mailbox) TokenRouter(_mailbox) {}

    /**
     * @notice Initializes the Hyperlane router, LSP8 metadata, and mints initial supply to deployer.
     * @param _mintAmount The amount of NFTs to mint to `msg.sender`.
     * @param _name The name of the token.
     * @param _symbol The symbol of the token.
     */
    function initialize(
        uint256 _mintAmount,
        string memory _name,
        string memory _symbol
    ) external initializer {
        address owner = msg.sender;
        _transferOwnership(owner);

        LSP8IdentifiableDigitalAssetInitAbstract._initialize(_name, _symbol, owner, _LSP4_TOKEN_TYPE_TOKEN, _LSP8_TOKENID_FORMAT_NUMBER);

        for (uint256 i = 0; i < _mintAmount; i++) {
            _mint(owner, bytes32(i), true, "");
        }
    }

    function balanceOf(
        address _account
    )
        public
        view
        virtual
        override(TokenRouter, LSP8IdentifiableDigitalAssetInitAbstract, ILSP8IdentifiableDigitalAsset)
        returns (uint256)
    {
        return LSP8IdentifiableDigitalAssetInitAbstract.balanceOf(_account);
    }

    /**
     * @dev Asserts `msg.sender` is owner and burns `_tokenId`.
     * @inheritdoc TokenRouter
     */
    function _transferFromSender(
        uint256 _tokenId
    ) internal virtual override returns (bytes memory) {
        require(ownerOf(_tokenId) == msg.sender, "!owner");
        _burn(_tokenId, "");
        return bytes(""); // no metadata
    }

    /**
     * @dev Mints `_tokenId` to `_recipient`.
     * @inheritdoc TokenRouter
     */
    function _transferTo(
        address _recipient,
        uint256 _tokenId,
        bytes calldata // no metadata
    ) internal virtual override {
        _mint(_recipient, _tokenId, true, "");
    }
}