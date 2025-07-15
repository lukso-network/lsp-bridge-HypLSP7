// SPDX-License-Identifier: MIT
pragma solidity >=0.8.22;

import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";

import { LSP8IdentifiableDigitalAssetInitAbstract } from
    "@lukso/lsp8-contracts/contracts/LSP8IdentifiableDigitalAssetInitAbstract.sol";

import { _LSP4_TOKEN_TYPE_COLLECTION, _LSP4_METADATA_KEY } from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";

import { _LSP8_TOKENID_FORMAT_NUMBER } from "@lukso/lsp8-contracts/contracts/LSP8Constants.sol";

/**
 * @title LSP8 version of the Hyperlane ERC721 Token Router
 * @dev See following links for reference:
 * - HypERC721 implementation:
 * https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/main/solidity/contracts/token/HypERC721.sol
 * - LSP8 standard: https://github.com/lukso-network/LIPs/blob/main/LSPs/LSP-8-IdentifiableDigitalAsset.md
 */
contract HypLSP8 is LSP8IdentifiableDigitalAssetInitAbstract, TokenRouter {
    constructor(address mailbox_) TokenRouter(mailbox_) { }

    /**
     * @notice Initializes the Hyperlane router, LSP8 metadata, and mints initial supply to deployer.
     *
     * @dev The `mintAmount` parameter is not used as minting synthetic NFTs when the warp route is created can lead
     * to accounting issues between chains. It would result in synthetic NFTs minted on the destination chain
     * while there is no NFTs locked in the collateral contract on the source chain.
     *
     * @param tokenName The name of the token.
     * @param tokenSymbol The symbol of the token.
     */
    function initialize(
        uint256, /* mintAmount */ // Unused but kept to not break compatibility with Hyperlane tools like CLI and SDK,
        string memory tokenName,
        string memory tokenSymbol,
        address defaultHook,
        address defaultInterchainSecurityModule,
        address contractOwner
    )
        external
        initializer
    {
        // Initializes the Hyperlane router
        _MailboxClient_initialize(defaultHook, defaultInterchainSecurityModule, contractOwner);

        // Initialize LSP8 collection metadata
        LSP8IdentifiableDigitalAssetInitAbstract._initialize({
            name_: tokenName,
            symbol_: tokenSymbol,
            newOwner_: contractOwner,
            // LSP4 Token Type is set to collection as each NFT is unique in design with uniquely identifiable IDs
            lsp4TokenType_: _LSP4_TOKEN_TYPE_COLLECTION,
            lsp8TokenIdFormat_: _LSP8_TOKENID_FORMAT_NUMBER
        });
    }

    function balanceOf(address account)
        public
        view
        virtual
        override(TokenRouter, LSP8IdentifiableDigitalAssetInitAbstract)
        returns (uint256)
    {
        return LSP8IdentifiableDigitalAssetInitAbstract.balanceOf(account);
    }

    /**
     * @dev Asserts `msg.sender` is owner and burns `tokenId`.
     * Note that this function will also trigger a callback to the `universalReceiver(...)` function
     * on the sender contract address.
     *
     * @inheritdoc TokenRouter
     */
    function _transferFromSender(uint256 tokenId) internal virtual override returns (bytes memory) {
        bytes32 tokenIdAsBytes32 = bytes32(tokenId);
        require(tokenOwnerOf(tokenIdAsBytes32) == msg.sender, "!owner");
        _burn(tokenIdAsBytes32, "");
        return bytes(""); // no metadata
    }

    /**
     * @dev Mints `tokenId` to `recipient`.
     * Note that this function will also trigger a callback to the `universalReceiver(...)` function
     * on the recipient contract address.
     *
     * @inheritdoc TokenRouter
     */
    function _transferTo(
        address recipient,
        uint256 tokenId,
        bytes calldata // no metadata
    )
        internal
        virtual
        override
    {
        _mint(recipient, bytes32(tokenId), true, "");
    }
}
