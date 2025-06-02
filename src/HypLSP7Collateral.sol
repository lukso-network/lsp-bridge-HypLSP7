// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

// Interfaces
import { ILSP7DigitalAsset as ILSP7 } from "@lukso/lsp7-contracts/contracts/ILSP7DigitalAsset.sol";

// Modules
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";

// Libraries
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IFreezer, IFreezeable, FrozenError } from "./ISM/FreezerUP.sol";
/**
 * @title Hyperlane + LUKSO LSP7 Token Collateral that wraps an existing LSP7 with remote transfer functionality.
 */

contract HypLSP7Collateral is TokenRouter, IFreezeable {
    // solhint-disable-next-line immutable-vars-naming
    ILSP7 public immutable wrappedToken;
    IFreezer freezer;

    /**
     * @notice Constructor
     *
     * @param lsp7_ Address of the token to keep as collateral
     */
    constructor(address lsp7_, address mailbox_) TokenRouter(mailbox_) {
        // solhint-disable-next-line custom-errors
        require(Address.isContract(lsp7_), "HypLSP7Collateral: invalid token");
        wrappedToken = ILSP7(lsp7_);
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

    function balanceOf(address _account) external view override returns (uint256) {
        return wrappedToken.balanceOf(_account);
    }

    /**
     * @dev Transfers `_amount` of `wrappedToken` from `msg.sender` to this contract.
     * Note that this function will also trigger a callback to the `universalReceiver(...)` function
     * on the `msg.sender` if it is a contract that supports + implements the LSP1 standard.
     *
     * @inheritdoc TokenRouter
     */
    function _transferFromSender(uint256 _amount) internal virtual override returns (bytes memory) {
        if (_frozen()) revert FrozenError();
        wrappedToken.transfer(msg.sender, address(this), _amount, true, "");
        return bytes(""); // no metadata
    }

    /**
     * @dev Transfers `_amount` of `wrappedToken` from this contract to `_recipient`.
     * Note that this function will also trigger a callback to the `universalReceiver(...)` function
     * on the `_recipient` if it is a contract that supports + implements the LSP1 standard.
     *
     * @inheritdoc TokenRouter
     */
    function _transferTo(
        address _recipient,
        uint256 _amount,
        bytes calldata // no metadata
    )
        internal
        virtual
        override
    {
        if (_frozen()) revert FrozenError();
        wrappedToken.transfer(address(this), _recipient, _amount, true, "");
    }

    function frozen() external view returns (bool) {
        return _frozen();
    }

    /**
     * This requires the Wrapped Token to have set up the CircuitBreaker in advance
     */
    function _frozen() internal view returns (bool) {
        // if _address is 0x0 address, this should still return false
        if (address(freezer) == address(0)) return false;
        return freezer.paused();
    }
}
