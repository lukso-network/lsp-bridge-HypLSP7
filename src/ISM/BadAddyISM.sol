// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

// ============= EXTERNAL ==============================
import { IInterchainSecurityModule } from "@hyperlane-xyz/core/contracts/interfaces/IInterchainSecurityModule.sol";
import { Message } from "@hyperlane-xyz/core/contracts/libs/Message.sol";
import { TokenMessage } from "@hyperlane-xyz/core/contracts/token/libs/TokenMessage.sol";
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";

// ============= INTERNAL ==============================
import { TokenMessageForLSP } from "../TokenMessageForLSP.sol";
import { Blockable } from "./Blockable.sol";

contract BadAddyIsm is IInterchainSecurityModule, Blockable {
    using TokenMessageForLSP for bytes;

    uint8 public constant override moduleType = uint8(Types.NULL);

    constructor(address owner) Blockable(owner) { }
    /**
     * Message->sender is the Local Token Contract on Origin Chain
     * Message->recipient is the TokenRouter on the Destination Chain
     * We must check the token recipient from the message body
     * We do not not (ATM) whether the format will be TokenMessage (HYP) or TokenMessageForLSP (LSP)
     * Because of limitations in Foundry pranking and how TokenMessageForLSP creates
     * the `sender` from msg.sender, we cannot test blocking bassed on the `sender` of the
     * Origin chain. This will need to be handled by an origin chain hook
     */

    function verify(bytes calldata, bytes calldata _message) public view override returns (bool) {
        bytes calldata _tokenMessage = Message.body(_message);
        // There is a question on what type of TokenMessage we will receive (it could also be TokenMessageForLSP)
        // Until that is clarified, we are validating against both
        address recipientHYP = TypeCasts.bytes32ToAddress(TokenMessage.recipient(_tokenMessage));
        address recipientLSP = TypeCasts.bytes32ToAddress(TokenMessageForLSP.recipient(_tokenMessage));
        if (blocked_addresses[recipientHYP] || blocked_addresses[recipientLSP]) {
            revert("!blocked");
        } else {
            return true;
        }
    }
}
