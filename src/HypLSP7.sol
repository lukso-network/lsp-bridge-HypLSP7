// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

// modules
import { LSP7DigitalAssetInitAbstract } from "@lukso/lsp7-contracts/contracts/LSP7DigitalAssetInitAbstract.sol";
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";

// constants
import { _LSP4_TOKEN_TYPE_TOKEN, _LSP4_METADATA_KEY } from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";
import { IFreezer, IFreezeable, FrozenError } from "./ISM/FreezerUP.sol";

/**
 * @title LSP7 version of the Hyperlane ERC20 Token Router
 * @dev See following links for reference:
 * - HypERC20 implementation:
 * https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/main/solidity/contracts/token/HypERC20.sol
 * - LSP7 standard: https://github.com/lukso-network/LIPs/blob/main/LSPs/LSP-7-DigitalAsset.md
 */
contract HypLSP7 is LSP7DigitalAssetInitAbstract, TokenRouter, IFreezeable {
    using TypeCasts for bytes32;

    // solhint-disable-next-line immutable-vars-naming
    uint8 private immutable _decimals;

    IFreezer freezer;

    constructor(uint8 __decimals, address _mailbox) TokenRouter(_mailbox) {
        _decimals = __decimals;
    }

    function initialize(
        uint256 _totalSupply,
        string memory _name,
        string memory _symbol,
        address _hook,
        address _interchainSecurityModule,
        address _owner,
        bytes memory _lsp4Metadata
    )
        external
    {
        _initialize(_totalSupply, _name, _symbol, _hook, _interchainSecurityModule, _owner, _lsp4Metadata, hex"00");
    }

    function initialize(
        uint256 _totalSupply,
        string memory _name,
        string memory _symbol,
        address _hook,
        address _interchainSecurityModule,
        address _owner,
        bytes memory _lsp4Metadata,
        bytes memory _freezer
    )
        external
    {
        _initialize(_totalSupply, _name, _symbol, _hook, _interchainSecurityModule, _owner, _lsp4Metadata, _freezer);
    }
    /**
     * @notice Initializes the Hyperlane router, LSP7 metadata, and mints initial supply to deployer.
     * @param _totalSupply The initial supply of the token.
     * @param _name The name of the token.
     * @param _symbol The symbol of the token.
     *
     * @dev The `LSP4TokenType` is hardcoded to type `Token` (= `0`) as all ERC20 tokens are of token type 0.
     * This aims to keep the number of parameters consistent between hyperc20 and hypLSP7, so that the code of off-chain
     * agents that call this function does not need to be modified to add an extra parameter that would be irrelevant.
     *
     * Note that a callback to the `universalReceiver(...)` function on the `msg.sender` contract address
     * will be triggered, even if the `_totalSupply` parameter passed is 0.
     */

    function _initialize(
        uint256 _totalSupply,
        string memory _name,
        string memory _symbol,
        address _hook,
        address _interchainSecurityModule,
        address _owner,
        bytes memory _lsp4Metadata,
        bytes memory _freezer
    )
        internal
        initializer
    {
        // Initialize LSP7 metadata
        LSP7DigitalAssetInitAbstract._initialize({
            name_: _name,
            symbol_: _symbol,
            newOwner_: _owner,
            lsp4TokenType_: _LSP4_TOKEN_TYPE_TOKEN,
            isNonDivisible_: false // isNonDivisible set to `false` as not used anyway since decimals() is overriden
         });

        // emit `DataChanged` event only if some metadata bytes is provided to save gas
        if (_lsp4Metadata.length > 0) {
            _setData(_LSP4_METADATA_KEY, _lsp4Metadata);
        }

        freezer = IFreezer(bytes32(_freezer).bytes32ToAddress());

        // mints initial supply to deployer
        LSP7DigitalAssetInitAbstract._mint({ to: msg.sender, amount: _totalSupply, force: true, data: "" });

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
        override(TokenRouter, LSP7DigitalAssetInitAbstract)
        returns (uint256)
    {
        return LSP7DigitalAssetInitAbstract.balanceOf(_account);
    }

    /**
     * @dev Burns `_amount` of token from `msg.sender` balance.
     * Note that this function will also trigger a callback to the `universalReceiver(...)` function
     * on the sender contract address.
     *
     * @inheritdoc TokenRouter
     */
    function _transferFromSender(uint256 _amount) internal override returns (bytes memory) {
        if (_frozen()) revert FrozenError();
        LSP7DigitalAssetInitAbstract._burn(msg.sender, _amount, "");
        return bytes(""); // no metadata
    }

    /**
     * @dev Mints `_amount` of token to `_recipient` balance.
     * Note that this function will also trigger a callback to the `universalReceiver(...)` function
     * on the recipient contract address.
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
        LSP7DigitalAssetInitAbstract._mint(_recipient, _amount, true, "");
    }

    function frozen() external view returns (bool) {
        return _frozen();
    }

    function _frozen() internal view returns (bool) {
        // if _address is 0x0 address, this should still return false?
        if (address(freezer) == address(0)) return false;
        return freezer.paused();
    }
}
