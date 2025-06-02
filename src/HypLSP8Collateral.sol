// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.19;

import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";

import { ILSP8IdentifiableDigitalAsset as ILSP8 } from
    "@lukso/lsp8-contracts/contracts/ILSP8IdentifiableDigitalAsset.sol";

import { IFreezer, IFreezeable, FrozenError } from "./ISM/FreezerUP.sol";

/**
 * @title Hyperlane LSP8 Token Collateral that wraps an existing LSP8 with remote transfer functionality.
 */
contract HypLSP8Collateral is TokenRouter, IFreezeable {
    // solhint-disable-next-line immutable-vars-naming
    ILSP8 public immutable wrappedToken;
    IFreezer freezer;

    /**
     * @notice Constructor
     *
     * @param lsp8_ Address of the token to keep as collateral
     */
    constructor(address lsp8_, address mailbox_) TokenRouter(mailbox_) {
        wrappedToken = ILSP8(lsp8_);
    }

    function initialize(address _hook, address _interchainSecurityModule, address _owner) public virtual {
        _initialize(_hook, _interchainSecurityModule, _owner, address(0));
    }

    function initialize(
        address _hook,
        address _interchainSecurityModule,
        address _owner,
        address _freezer
    )
        public
        virtual
    {
        _initialize(_hook, _interchainSecurityModule, _owner, _freezer);
    }

    /**
     * @notice Initializes the Hyperlane router
     *
     * @param _hook The post-dispatch hook contract.
     * @param _interchainSecurityModule The interchain security module contract.
     * @param _owner The this contract.
     */
    function _initialize(
        address _hook,
        address _interchainSecurityModule,
        address _owner,
        address _freezer
    )
        internal
        virtual
        initializer
    {
        _MailboxClient_initialize(_hook, _interchainSecurityModule, _owner);
        freezer = IFreezer(_freezer);
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
        if (_frozen()) revert FrozenError();
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
        if (_frozen()) revert FrozenError();
        wrappedToken.transfer(address(this), _recipient, bytes32(_tokenId), true, "");
    }

    function frozen() external view returns (bool) {
        return _frozen();
    }

    /**
     * This requires the Wrapped Token to have set up the Freezer in advance
     */
    function _frozen() internal view returns (bool) {
        // if _address is 0x0 address, this should still return false
        if (address(freezer) == address(0)) return false;
        return freezer.paused();
    }
}
