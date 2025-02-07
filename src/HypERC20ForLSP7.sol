// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

// modules
import { HypERC20 } from "@hyperlane-xyz/core/contracts/token/HypERC20.sol";
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";

// libraries
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import { TokenMessageForLSP } from "./TokenMessageForLSP.sol";

/**
 * @title Hyperlane ERC20 Synthetic Token Router on a destination chain linked to a LSP7 token on a source chain.
 * @dev This contract extends ERC20 with remote transfer functionality.
 * @author CJ42 (lukso.network, adapted from Abacus Works)
 */
contract HypERC20ForLSP7 is HypERC20 {
    constructor(uint8 __decimals, address _mailbox) HypERC20(__decimals, _mailbox) { }

    /**
     * @dev Mints tokens to recipient when router receives transfer message.
     * @dev Emits `ReceivedTransferRemote` event on the destination chain.
     * @param _origin The identifier of the origin chain.
     * @param _message The encoded remote transfer message containing the recipient address and amount.
     *
     * @dev This function is overriden to extract the right params and calldata slices
     * from a `LSP7.transfer(...)` message, via the modified library `TokenMessageForLSP`.
     */
    function _handle(uint32 _origin, bytes32, bytes calldata _message) internal virtual override(TokenRouter) {
        bytes32 recipient = TokenMessageForLSP.recipient(_message);
        uint256 amount = TokenMessageForLSP.amount(_message);
        bytes calldata metadata = TokenMessageForLSP.metadata(_message);
        _transferTo(TypeCasts.bytes32ToAddress(recipient), amount, metadata);
        emit ReceivedTransferRemote(_origin, recipient, amount);
    }
}
