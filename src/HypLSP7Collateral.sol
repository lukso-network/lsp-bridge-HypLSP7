// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

// Interfaces
import { ILSP7DigitalAsset as ILSP7 } from "@lukso/lsp7-contracts/contracts/ILSP7DigitalAsset.sol";

// Modules
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";

// Libraries
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title LSP7 version of the Hyperlane ERC20 Token Collateral that wraps an existing LSP7 with remote transfer
 * functionality
 * @dev See following links for reference:
 * - HypERC20Collateral implementation:
 * https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/main/solidity/contracts/token/HypERC20Collateral.sol
 * - LSP7 standard: https://github.com/lukso-network/LIPs/blob/main/LSPs/LSP-7-DigitalAsset.md
 */
contract HypLSP7Collateral is TokenRouter {
    // solhint-disable-next-line immutable-vars-naming
    ILSP7 public immutable wrappedToken;

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
        wrappedToken.transfer(address(this), _recipient, _amount, true, "");
    }
}
