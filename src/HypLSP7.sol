// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

// modules
import { LSP7DigitalAssetInitAbstract, LSP7DigitalAssetCore } from "@lukso/lsp7-contracts/contracts/LSP7DigitalAssetInitAbstract.sol";
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { OwnableUnset } from "@erc725/smart-contracts/contracts/custom/OwnableUnset.sol";

/**
 * @title LSP7 version of the Hyperlane ERC20 Token Router
 * @dev https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/main/solidity/contracts/token/HypERC20.sol
 */
contract HypLSP7 is LSP7DigitalAssetInitAbstract, TokenRouter {
    uint8 private immutable _decimals;

    modifier onlyOwner() virtual override(OwnableUnset, OwnableUpgradeable) {
        _checkOwner();
        _;
    }

    constructor(uint8 __decimals, address _mailbox) TokenRouter(_mailbox) {
        _decimals = __decimals;
    }

    /**
     * @notice Initializes the Hyperlane router, LSP7 metadata, and mints initial supply to deployer.
     * @param _totalSupply The initial supply of the token.
     * @param _name The name of the token.
     * @param _symbol The symbol of the token.
     */
    function initialize(
        uint256 _totalSupply,
        string memory _name,
        string memory _symbol,
        address _hook,
        address _interchainSecurityModule,
        address _owner,
        uint256 _lsp4TokenType
    )
        external
        initializer
    {
        // Initialize LSP7 metadata
        LSP7DigitalAssetInitAbstract._initialize({
            name_: _name,
            symbol_: _symbol,
            newOwner_: _owner,
            lsp4TokenType_: _lsp4TokenType,
            isNonDivisible_: false // isNonDivisible set to `false` as will not be used anyway since decimals() is
                // overriden
         });

        // mints initial supply to deployer
        LSP7DigitalAssetCore._mint({ to: msg.sender, amount: _totalSupply, force: true, data: "" });

        // Initializes the Hyperlane router
        _MailboxClient_initialize(_hook, _interchainSecurityModule, _owner);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function balanceOf(address _account)
        public
        view
        virtual
        override(TokenRouter, LSP7DigitalAssetCore)
        returns (uint256)
    {
        return LSP7DigitalAssetCore.balanceOf(_account);
    }

    function owner() public view virtual override(OwnableUnset, OwnableUpgradeable) returns (address) {
        return OwnableUpgradeable.owner();
    }

    function renounceOwnership() public virtual override(OwnableUnset, OwnableUpgradeable) onlyOwner {
        OwnableUpgradeable.renounceOwnership();
    }

    function transferOwnership(address newOwner) public virtual override(OwnableUnset, OwnableUpgradeable) onlyOwner {
        OwnableUpgradeable.transferOwnership(newOwner);
    }

    /**
     * @dev Burns `_amount` of token from `msg.sender` balance.
     * @inheritdoc TokenRouter
     */
    function _transferFromSender(
        uint256 _amount
    ) internal override returns (bytes memory) {
        LSP7DigitalAssetCore._burn(msg.sender, _amount, "");
        return bytes(""); // no metadata
    }

    /**
     * @dev Mints `_amount` of token to `_recipient` balance.
     * @inheritdoc TokenRouter
     */
    function _transferTo(
        address _recipient,
        uint256 _amount,
        bytes calldata // no metadata
    ) internal virtual override {
        LSP7DigitalAssetCore._mint(_recipient, _amount, true, "");
    }

     function _checkOwner() internal view override(OwnableUnset, OwnableUpgradeable) {
        OwnableUpgradeable._checkOwner();
    }
}