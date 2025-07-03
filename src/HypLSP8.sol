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
     * @dev The `mintAmount` parameter is mostly used for a brand new NFT that want to exists only as a warp route.
     * In other words, the entire warp route is deployed with HypLSP8, and no HypLSP8Collateral.
     * This enables to create an instantly bridgable NFT, by deploying the contract, minting and distributing the token
     * supply.
     * For existing NFT collections that already exist on the source chain, set this parameter to 0.
     *
     * LSP8 specific notice: note that a callback to the `universalReceiver(...)` function
     * on the `msg.sender` contract address will be triggered for every single tokenId
     * being minted if the `mintAmount` is set to more than 0.
     *
     * @param mintAmount The amount of NFTs to mint to `msg.sender`.
     * @param tokenName The name of the token.
     * @param tokenSymbol The symbol of the token.
     */
    function initialize(
        uint256 mintAmount,
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

        for (uint256 i = 0; i < mintAmount; i++) {
            _mint(msg.sender, bytes32(i), true, "");
        }
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
