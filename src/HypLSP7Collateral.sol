// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

// Interfaces
import { ILSP7DigitalAsset as ILSP7 } from "@lukso/lsp7-contracts/contracts/ILSP7DigitalAsset.sol";
import { IERC725Y } from "@erc725/smart-contracts/contracts/interfaces/IERC725Y.sol";

// Modules
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";

// Libraries
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { OwnableUnset } from "@erc725/smart-contracts/contracts/custom/OwnableUnset.sol";

import { ICircuitBreaker, ICircuitBreakable, _HypLSP_CIRCUIT_BREAKER_KEY, CircuitError } from "./ISM/CircuitBreaker.sol";

/**
 * @title Hyperlane + LUKSO LSP7 Token Collateral that wraps an existing LSP7 with remote transfer functionality.
 */
contract HypLSP7Collateral is TokenRouter, ICircuitBreakable {
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
        if(_circuitBroken()) { revert  CircuitError(); }
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
        if(_circuitBroken()) { revert  CircuitError(); }
        wrappedToken.transfer(address(this), _recipient, _amount, true, "");
    }

    function circuitBroken() external view returns(bool) {
        return _circuitBroken();
    }

    /**
    This requires the Wrapped Token to have set up the CircuitBreaker in advance
     */
    function _circuitBroken() internal view returns(bool) {
        IERC725Y erc725y = IERC725Y(address(wrappedToken));
        bytes memory data = erc725y.getData(_HypLSP_CIRCUIT_BREAKER_KEY);
        address cbaddress = address(bytes20(data));
        ICircuitBreaker circuitBreaker = ICircuitBreaker(cbaddress);
        // if _address is 0x0 address, this should still return false
        if(address(circuitBreaker) == address(0)) { return false; }
        return circuitBreaker.paused();
    }

    /**
    I'm not convinced all the following overrides is worth introducing ERC725Y just to set
    a single data point
    It could be MUCH cleaner just to store the address in a local variable
    
    //  */
    // function _checkOwner() internal view virtual override(OwnableUpgradeable, OwnableUnset) {
    //     OwnableUpgradeable._checkOwner();
    // }

    // function renounceOwnership() public virtual override(OwnableUpgradeable, OwnableUnset) {
    //     OwnableUpgradeable.renounceOwnership();
    // }

    // function transferOwnership(address newOwner) public virtual override(OwnableUpgradeable, OwnableUnset) {
    //     OwnableUpgradeable.transferOwnership(newOwner);
    // }

    // function owner() public view virtual override(OwnableUpgradeable, OwnableUnset) returns (address) {
    //     return OwnableUpgradeable.owner();
    // }

    // // modifier onlyOwner() override(OwnableUpgradeable, OwnableUnset) {
    // //     _checkOwner();
    // //     _;
    // // }
}
