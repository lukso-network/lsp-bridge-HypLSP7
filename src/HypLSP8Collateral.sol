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
 * @title Hyperlane LSP8 Token Collateral that wraps an existing LSP8 with remote transfer functionality.
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
     * @param _hook The post-dispatch hook contract.
     * @param _interchainSecurityModule The interchain security module contract.
     * @param _owner The this contract.
     */
    function initialize(address _hook, address _interchainSecurityModule, address _owner) public virtual initializer {
        _MailboxClient_initialize(_hook, _interchainSecurityModule, _owner);
    }

    function ownerOf(uint256 _tokenId) external view returns (address) {
        return wrappedToken.tokenOwnerOf(bytes32(_tokenId));
    }

    /**
     * @dev Returns the balance of `_account` for `wrappedToken`.
     * @inheritdoc TokenRouter
     */
    function balanceOf(address _account) external view override returns (uint256) {
        return wrappedToken.balanceOf(_account);
    }

    /**
     * @dev Transfers `_tokenId` of `wrappedToken` from `msg.sender` to this contract.
     * Note that this function will also trigger a callback to the `universalReceiver(...)` function
     * on the `msg.sender` if it is a contract that supports + implements the LSP1 standard.
     *
     * @inheritdoc TokenRouter
     */
    function _transferFromSender(uint256 _tokenId) internal virtual override returns (bytes memory) {
        wrappedToken.transfer(msg.sender, address(this), bytes32(_tokenId), true, "");
        return bytes(""); // no metadata
    }

    /**
     * @dev Transfers `_tokenId` of `wrappedToken` from this contract to `_recipient`.
     * Note that this function will also trigger a callback to the `universalReceiver(...)` function
     * on the `_recipient` if it is a contract that supports + implements the LSP1 standard.
     *
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
