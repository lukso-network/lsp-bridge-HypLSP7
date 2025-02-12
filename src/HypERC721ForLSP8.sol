// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

// modules
import { HypERC721 } from "@hyperlane-xyz/core/contracts/token/HypERC721.sol";

// libraries
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import { TokenMessageForLSP } from "./TokenMessageForLSP.sol";

/**
 * @title Hyperlane ERC721 Synthetic Token Router on a destination chain linked to a LSP8 token on a source chain.
 * @dev This contract extends ERC721 with remote transfer functionality.
 * @author CJ42 (lukso.network, adapted from Abacus Works)
 */
contract HypERC721ForLSP8 is HypERC721 {
    constructor(uint8 __decimals, address _mailbox) HypERC721(_mailbox) { }

    /**
     * @dev Mints a tokenId to recipient when router receives transfer message.
     * @dev Emits `ReceivedTransferRemote` event on the destination chain.
     * @param _origin The identifier of the origin chain.
     * @param _message The encoded remote transfer message containing the recipient address and tokenId.
     *
     * @dev This function is overriden to extract the right params and calldata slices
     * from a `LSP8.transfer(...)` message, via the modified library `TokenMessageForLSP`.
     */
    function _handle(uint32 _origin, bytes32, bytes calldata _message) internal virtual override {
        bytes32 recipient = TokenMessageForLSP.recipient(_message);
        bytes32 tokenId = TokenMessageForLSP.tokenId(_message);
        bytes calldata metadata = TokenMessageForLSP.metadata(_message);

        // Explicit conversion as tokenId on ERC721 are represented as `uint256`.
        _transferTo(TypeCasts.bytes32ToAddress(recipient), uint256(tokenId), metadata);
        emit ReceivedTransferRemote(_origin, recipient, uint256(tokenId));
    }
}
