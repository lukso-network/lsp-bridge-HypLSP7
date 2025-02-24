// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;
import { console } from "../../lib/forge-std/src/console.sol";

// ============= EXTERNAL ==============================
import { IInterchainSecurityModule } from "@hyperlane-xyz/core/contracts/interfaces/IInterchainSecurityModule.sol";
import { Message } from "@hyperlane-xyz/core/contracts/libs/Message.sol";
import { TypeCasts } from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// ============= INTERNAL ==============================
import { TokenMessageForLSP } from "../TokenMessageForLSP.sol";
import { CircuitBreakerAdapter } from "./CircuitBreakerAdapter.sol";

event BlockedAddress(address _blockedAddress);

contract BadAddyIsm is IInterchainSecurityModule, CircuitBreakerAdapter {	
    using TokenMessageForLSP for bytes;

    uint8 public constant override moduleType = uint8(Types.NULL);
	
    mapping(address => bool) private blocked_addresses;

    constructor(address owner) CircuitBreakerAdapter() {
        _transferOwnership(owner);
    }
    /**
    Message->sender is the Local Token Contract on Origin Chain
    Message->recipient is the TokenRouter on the Destination Chain
    We must check the token recipient and sender from the message body
    For this we use TokenMessageForLSP 
     */
    function verify(
        bytes calldata,
        bytes calldata _message
    ) public view override returns (bool) {
        bytes calldata _tokenMessage = Message.body(_message);
        address sender  = TypeCasts.bytes32ToAddress(TokenMessageForLSP.sender(_tokenMessage));
        address recipient = TypeCasts.bytes32ToAddress(TokenMessageForLSP.recipient(_tokenMessage));
        console.log("BADDY VERIFY()");
        console.log("Sender");
        console.log(sender);
        console.log("Recipient");
        console.log(recipient);
        if(blocked_addresses[recipient] || blocked_addresses[sender]) {
            revert("!blocked");
        } else {
	        return true;
        }
    }

    function blockAddress(address _address) external isCircuitBreakerOrOwner {
        blocked_addresses[_address] = true;
        emit BlockedAddress(_address);
    }
}
