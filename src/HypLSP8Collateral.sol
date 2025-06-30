// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.19;

// Interfaces
import { ILSP8IdentifiableDigitalAsset as ILSP8 } from
    "@lukso/lsp8-contracts/contracts/ILSP8IdentifiableDigitalAsset.sol";

// Modules
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";

// Libraries
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title LSP8 version of the Hyperlane ERC721 Token Collateral that wraps an existing LSP8 with remote transfer
 * functionality
 * @dev See following links for reference:
 * - HypERC721Collateral implementation:
 * https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/main/solidity/contracts/token/HypERC721Collateral.sol
 * - LSP8 standard: https://github.com/lukso-network/LIPs/blob/main/LSPs/LSP-8-IdentifiableDigitalAsset.md
 */
contract HypLSP8Collateral is TokenRouter {
    // solhint-disable-next-line immutable-vars-naming
    ILSP8 public immutable wrappedToken;

    /**
     * @notice Constructor
     *
     * @param lsp8_ Address of the token to keep as collateral
     */
    constructor(address lsp8_, address mailbox_) TokenRouter(mailbox_) {
        // solhint-disable-next-line custom-errors
        require(Address.isContract(lsp8_), "HypLSP8Collateral: invalid token");
        wrappedToken = ILSP8(lsp8_);
    }

    /**
     * @notice Initializes the Hyperlane router
     *
     * @param defaultHook The post-dispatch hook contract.
     * @param defaultInterchainSecurityModule The interchain security module contract.
     * @param contractOwner The this contract.
     */
    function initialize(
        address defaultHook,
        address defaultInterchainSecurityModule,
        address contractOwner
    )
        public
        virtual
        initializer
    {
        _MailboxClient_initialize(defaultHook, defaultInterchainSecurityModule, contractOwner);
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        return wrappedToken.tokenOwnerOf(bytes32(tokenId));
    }

    /**
     * @dev Returns the balance of `account` for `wrappedToken`.
     * @inheritdoc TokenRouter
     */
    function balanceOf(address account) external view override returns (uint256) {
        return wrappedToken.balanceOf(account);
    }

    /**
     * @dev Transfers `tokenId` of `wrappedToken` from `msg.sender` to this contract.
     * Note that this function will also trigger a callback to the `universalReceiver(...)` function
     * on the `msg.sender` if it is a contract that supports + implements the LSP1 standard.
     *
     * @inheritdoc TokenRouter
     */
    function _transferFromSender(uint256 tokenId) internal virtual override returns (bytes memory) {
        wrappedToken.transfer(msg.sender, address(this), bytes32(tokenId), true, "");
        return bytes(""); // no metadata
    }

    /**
     * @dev Transfers `tokenId` of `wrappedToken` from this contract to `recipient`.
     * Note that this function will also trigger a callback to the `universalReceiver(...)` function
     * on the `recipient` if it is a contract that supports + implements the LSP1 standard.
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
        wrappedToken.transfer(address(this), recipient, bytes32(tokenId), true, "");
    }
}
