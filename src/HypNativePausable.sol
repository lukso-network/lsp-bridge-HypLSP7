// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import { HypNative } from "@hyperlane-xyz/core/contracts/token/HypNative.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IFreezer, IFreezeable, FrozenError } from "./ISM/FreezerUP.sol";

contract HypNativePausable is HypNative, IFreezeable {
    IFreezer freezer;

    constructor(address mailbox) HypNative(mailbox) { }

    /**
     * HypNative `initialize()` is not marked as virtual so we cannot override it to provide
     * an option for initializing a Freezer contract.
     */
    function setFreezer(address _freezer) public onlyOwner {
        freezer = IFreezer(_freezer);
    }

    /**
     * @dev Sends `_amount` of native token to `_recipient` balance.
     * @inheritdoc HypNative
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
        Address.sendValue(payable(_recipient), _amount);
    }

    /**
     * @inheritdoc HypNative
     * @dev uses (`msg.value` - `_amount`) as hook payment and `msg.sender` as refund address.
     */
    function transferRemote(
        uint32 _destination,
        bytes32 _recipient,
        uint256 _amount
    )
        external
        payable
        virtual
        override(HypNative)
        returns (bytes32 messageId)
    {
        if (_frozen()) revert FrozenError();
        require(msg.value >= _amount, "Native: amount exceeds msg.value");
        uint256 _hookPayment = msg.value - _amount;
        return _transferRemote(_destination, _recipient, _amount, _hookPayment);
    }

    /**
     * @inheritdoc HypNative
     * @dev uses (`msg.value` - `_amount`) as hook payment.
     */
    function transferRemote(
        uint32 _destination,
        bytes32 _recipient,
        uint256 _amount,
        bytes calldata _hookMetadata,
        address _hook
    )
        external
        payable
        virtual
        override
        returns (bytes32 messageId)
    {
        if (_frozen()) revert FrozenError();
        require(msg.value >= _amount, "Native: amount exceeds msg.value");
        uint256 _hookPayment = msg.value - _amount;
        return _transferRemote(_destination, _recipient, _amount, _hookPayment, _hookMetadata, _hook);
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
