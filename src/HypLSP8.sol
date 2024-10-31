// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.19;

import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";

import { LSP8IdentifiableDigitalAssetInitAbstract } from
    "@lukso/lsp8-contracts/contracts/LSP8IdentifiableDigitalAssetInitAbstract.sol";

import { _LSP4_TOKEN_TYPE_TOKEN } from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";

import { _LSP8_TOKENID_FORMAT_NUMBER } from "@lukso/lsp8-contracts/contracts/LSP8Constants.sol";

/**
 * @title LSP8 version of the Hyperlane ERC721 Token Router
 * @dev https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/main/solidity/contracts/token/HypERC721.sol
 */
contract HypLSP8 is LSP8IdentifiableDigitalAssetInitAbstract, TokenRouter {
    constructor(address _mailbox) TokenRouter(_mailbox) { }

    /**
     * @notice Initializes the Hyperlane router, LSP8 metadata, and mints initial supply to deployer.
     * @param _mintAmount The amount of NFTs to mint to `msg.sender`.
     * @param _name The name of the token.
     * @param _symbol The symbol of the token.
     */
    function initialize(
        uint256 _mintAmount,
        address _hook,
        address _interchainSecurityModule,
        address _owner,
        string memory _name,
        string memory _symbol
    )
        external
        initializer
    {
        _MailboxClient_initialize(_hook, _interchainSecurityModule, _owner);
        address owner = msg.sender;
        _transferOwnership(owner);

        LSP8IdentifiableDigitalAssetInitAbstract._initialize(
            _name, _symbol, owner, _LSP4_TOKEN_TYPE_TOKEN, _LSP8_TOKENID_FORMAT_NUMBER
        );

        for (uint256 i = 0; i < _mintAmount; i++) {
            _mint(owner, bytes32(i), true, "");
        }
    }

    function balanceOf(address _account)
        public
        view
        virtual
        override(TokenRouter, LSP8IdentifiableDigitalAssetInitAbstract)
        returns (uint256)
    {
        return LSP8IdentifiableDigitalAssetInitAbstract.balanceOf(_account);
    }

    /**
     * @dev Asserts `msg.sender` is owner and burns `_tokenId`.
     * @inheritdoc TokenRouter
     */
    function _transferFromSender(uint256 _tokenId) internal virtual override returns (bytes memory) {
        bytes32 tokenIdAsBytes32 = bytes32(_tokenId);
        require(tokenOwnerOf(tokenIdAsBytes32) == msg.sender, "!owner");
        _burn(tokenIdAsBytes32, "");
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
    )
        internal
        virtual
        override
    {
        _mint(_recipient, bytes32(_tokenId), true, "");
    }
}
