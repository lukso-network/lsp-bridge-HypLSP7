// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.19;

import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";

import { LSP8IdentifiableDigitalAssetInitAbstract } from
    "@lukso/lsp8-contracts/contracts/LSP8IdentifiableDigitalAssetInitAbstract.sol";

import { _LSP4_TOKEN_TYPE_NFT, _LSP4_METADATA_KEY } from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";

import { _LSP8_TOKENID_FORMAT_NUMBER } from "@lukso/lsp8-contracts/contracts/LSP8Constants.sol";

/**
 * @title LSP8 version of the Hyperlane ERC721 Token Router
 * @dev See following links for reference:
 * - HypERC721 implementation:
 * https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/main/solidity/contracts/token/HypERC721.sol
 * - LSP8 standard: https://github.com/lukso-network/LIPs/blob/main/LSPs/LSP-8-IdentifiableDigitalAsset.md
 */
contract HypLSP8 is LSP8IdentifiableDigitalAssetInitAbstract, TokenRouter {
    error InvalidRecipientError();

    constructor(address _mailbox) TokenRouter(_mailbox) { }

    /**
     * @notice Initializes the Hyperlane router, LSP8 metadata, and mints initial supply to deployer.
     *
     * @dev The `_mintAmount` parameter is mostly used for a brand new NFT that want to exists only as a warp route.
     * In other words, the entire warp route is deployed with HypLSP8, and no HypLSP8Collateral.
     * This enables to create an instantly bridgable NFT, by deploying the contract, minting and distributing the token
     * supply.
     * For existing NFT collections that already exist on the source chain, set this parameter to 0.
     *
     * LSP8 specific notice: note that a callback to the `universalReceiver(...)` function
     * on the `msg.sender` contract address will be triggered for every single tokenId
     * being minted if the `_mintAmount` is set to more than 0.
     *
     * @param _mintAmount The amount of NFTs to mint to `msg.sender`.
     * @param _name The name of the token.
     * @param _symbol The symbol of the token.
     */
    function initialize(
        uint256 _mintAmount,
        string memory _name,
        string memory _symbol,
        address _hook,
        address _interchainSecurityModule,
        address _owner,
        bytes memory _lsp4Metadata
    )
        external
        initializer
    {
        // Initializes the Hyperlane router
        _MailboxClient_initialize(_hook, _interchainSecurityModule, _owner);

        // Initialize LSP8 collection metadata
        LSP8IdentifiableDigitalAssetInitAbstract._initialize(
            _name, _symbol, _owner, _LSP4_TOKEN_TYPE_NFT, _LSP8_TOKENID_FORMAT_NUMBER
        );

        // emit `DataChanged` event only if some metadata bytes is provided to save gas
        if (_lsp4Metadata.length > 0) {
            _setData(_LSP4_METADATA_KEY, _lsp4Metadata);
        }

        for (uint256 i = 0; i < _mintAmount; i++) {
            _mint(msg.sender, bytes32(i), true, "");
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
     * Note that this function will also trigger a callback to the `universalReceiver(...)` function
     * on the sender contract address.
     *
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
     * Note that this function will also trigger a callback to the `universalReceiver(...)` function
     * on the recipient contract address.
     *
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

    /**
     * @inheritdoc TokenRouter
     * @dev Ensures that the recipient of the token transfer is not the collateral contract
     */
    function transferRemote(
        uint32 _destination,
        bytes32 _recipient,
        uint256 _amountOrId
    )
        external
        payable
        override
        returns (bytes32 messageId)
    {
        if (_recipient == routers(_destination)) revert InvalidRecipientError();
        return _transferRemote(_destination, _recipient, _amountOrId, msg.value);
    }

    /**
     * @inheritdoc TokenRouter
     * @dev Ensures that the recipient of the token transfer is not the collateral contract
     */
    function transferRemote(
        uint32 _destination,
        bytes32 _recipient,
        uint256 _amountOrId,
        bytes calldata _hookMetadata,
        address _hook
    )
        external
        payable
        override
        returns (bytes32 messageId)
    {
        if (_recipient == routers(_destination)) revert InvalidRecipientError();
        return _transferRemote(_destination, _recipient, _amountOrId, msg.value, _hookMetadata, _hook);
    }
}
