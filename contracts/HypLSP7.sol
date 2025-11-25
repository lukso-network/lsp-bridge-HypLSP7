// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.22;

// modules
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";
import { FungibleTokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/FungibleTokenRouter.sol";
import { LSP7DigitalAssetInitAbstract } from "@lukso/lsp7-contracts/contracts/LSP7DigitalAssetInitAbstract.sol";

// constants
import { _LSP4_TOKEN_TYPE_TOKEN } from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";

/**
 * @title LSP7 version of the Hyperlane ERC20 Token Router
 * @dev See following links for reference:
 * - HypERC20 implementation:
 * https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/main/solidity/contracts/token/HypERC20.sol
 * - LSP7 standard: https://github.com/lukso-network/LIPs/blob/main/LSPs/LSP-7-DigitalAsset.md
 */
contract HypLSP7 is LSP7DigitalAssetInitAbstract, FungibleTokenRouter {
    // solhint-disable-next-line immutable-vars-naming
    uint8 private immutable _decimals;

    constructor(uint8 decimals_, uint256 scale_, address mailbox_) FungibleTokenRouter(scale_, mailbox_) {
        _decimals = decimals_;
    }

    /**
     * @notice Initializes the Hyperlane router, LSP7 metadata, and mints initial supply to deployer.
     * @param tokenName The name of the token.
     * @param tokenSymbol The symbol of the token.
     *
     * @dev The `LSP4TokenType` is hardcoded to type `Token` (= `0`) as all ERC20 tokens are of token type 0.
     *
     * @dev The `initialSupply` parameter is not used as minting synthetic tokens when the warp route is created
     * can lead to accounting issues between chains. It would result in synthetic tokens minted on the destination chain
     * while there is no tokens locked in the collateral contract on the source chain.
     */
    function initialize(
        uint256, // initialSupply Unused but kept to not break compatibility with Hyperlane tools like CLI and SDK
        string memory tokenName,
        string memory tokenSymbol,
        address defaultHook,
        address defaultInterchainSecurityModule,
        address contractOwner
    )
        external
        initializer
    {
        // Initialize LSP7 metadata
        LSP7DigitalAssetInitAbstract._initialize({
            name_: tokenName,
            symbol_: tokenSymbol,
            newOwner_: contractOwner,
            lsp4TokenType_: _LSP4_TOKEN_TYPE_TOKEN,
            // Even if the `_isNonDivisible` state variable is not used because it is overriden by the `decimals()`
            // function below, ensure its value is set correctly in the proxy contract's storage,
            // according to the `_decimals` immutable variable derived from the implementation.
            isNonDivisible_: _decimals == 0
        });

        // Initializes the warp route
        _MailboxClient_initialize(defaultHook, defaultInterchainSecurityModule, contractOwner);
    }

    /// @dev Override the default `decimals()` function that relies on `isNonDivisible_` parameter
    /// to use the `_decimals` immutable variable set above instead.
    function decimals() public view virtual override(LSP7DigitalAssetInitAbstract) returns (uint8) {
        return _decimals;
    }

    function balanceOf(address account)
        public
        view
        virtual
        override(TokenRouter, LSP7DigitalAssetInitAbstract)
        returns (uint256)
    {
        return LSP7DigitalAssetInitAbstract.balanceOf(account);
    }

    /**
     * @dev Burns `amount` of token from `msg.sender` balance.
     * Note that this function will also trigger a callback to the `universalReceiver(...)` function
     * on the sender contract address.
     *
     * @inheritdoc TokenRouter
     */
    function _transferFromSender(uint256 amount) internal override returns (bytes memory) {
        LSP7DigitalAssetInitAbstract._burn(msg.sender, amount, "");
        return bytes(""); // no metadata
    }

    /**
     * @dev Mints `amount` of token to `recipient` balance.
     * Note that this function will also trigger a callback to the `universalReceiver(...)` function
     * on the recipient contract address.
     *
     * @inheritdoc TokenRouter
     */
    function _transferTo(
        address recipient,
        uint256 amount,
        bytes calldata // no metadata
    )
        internal
        virtual
        override
    {
        LSP7DigitalAssetInitAbstract._mint(recipient, amount, true, "");
    }
}
