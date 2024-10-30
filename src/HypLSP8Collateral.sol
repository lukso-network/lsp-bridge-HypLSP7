// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.19;

import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";

import { TokenMessage } from "@hyperlane-xyz/core/contracts/token/libs/TokenMessage.sol";

import { ILSP8IdentifiableDigitalAsset } from "@lukso/lsp8-contracts/contracts/ILSP8IdentifiableDigitalAsset.sol";

/**
 * @title Hyperlane LSP8 Token Collateral that wraps an existing LSP8 with remote transfer functionality.
 * @author Abacus Works
 */
contract HypLSP8Collateral is TokenRouter {
    ILSP8IdentifiableDigitalAsset public immutable wrappedToken;

    /**
     * @notice Constructor
     * @param lsp8 Address of the token to keep as collateral
     */
    constructor(address lsp8, address _mailbox) TokenRouter(_mailbox) {
        wrappedToken = ILSP8IdentifiableDigitalAsset(lsp8);
    }

    /**
     * @notice Initializes the Hyperlane router
     * @param _hook The post-dispatch hook contract.
     *    @param _interchainSecurityModule The interchain security module contract.
     *    @param _owner The this contract.
     */
    function initialize(address _hook, address _interchainSecurityModule, address _owner) public virtual initializer {
        _MailboxClient_initialize(_hook, _interchainSecurityModule, _owner);
    }

    function ownerOf(uint256 _tokenId) external view returns (address) {
        return ILSP8IdentifiableDigitalAsset(wrappedToken).tokenOwnerOf(bytes32(_tokenId));
    }

    /**
     * @dev Returns the balance of `_account` for `wrappedToken`.
     * @inheritdoc TokenRouter
     */
    function balanceOf(address _account) external view override returns (uint256) {
        return ILSP8IdentifiableDigitalAsset(wrappedToken).balanceOf(_account);
    }

    /**
     * @dev Transfers `_tokenId` of `wrappedToken` from `msg.sender` to this contract.
     * @inheritdoc TokenRouter
     */
    function _transferFromSender(uint256 _tokenId) internal virtual override returns (bytes memory) {
        wrappedToken.transfer(msg.sender, address(this), bytes32(_tokenId), true, "");
        return bytes(""); // no metadata
    }

    /**
     * @dev Transfers `_tokenId` of `wrappedToken` from this contract to `_recipient`.
     * @inheritdoc TokenRouter
     */
    function _transferTo(
        address _recipient,
        uint256 _tokenId,
        bytes calldata // no metadata
    )
        internal
        override
    {
        wrappedToken.transfer(address(this), _recipient, bytes32(_tokenId), true, "");
    }
}
