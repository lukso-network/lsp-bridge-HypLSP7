// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import { HypNative } from "@hyperlane-xyz/core/contracts/token/HypNative.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {CircuitBreakerAdapter} from "./ISM/CircuitBreakerAdapter.sol";

contract HypNativePausable is HypNative, CircuitBreakerAdapter {

    constructor(address mailbox) HypNative(mailbox) { }

    /**
     * @dev Sends `_amount` of native token to `_recipient` balance.
     * @inheritdoc HypNative
     */
    function _transferTo(
        address _recipient,
        uint256 _amount,
        bytes calldata // no metadata
    ) internal virtual override whenNotPaused {
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
    ) external payable virtual override(HypNative) whenNotPaused returns (bytes32 messageId) {
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
    ) external payable virtual override whenNotPaused returns (bytes32 messageId) {
        require(msg.value >= _amount, "Native: amount exceeds msg.value");
        uint256 _hookPayment = msg.value - _amount;
        return
            _transferRemote(
                _destination,
                _recipient,
                _amount,
                _hookPayment,
                _hookMetadata,
                _hook
            );
    }
}
