// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import { console } from "forge-std/src/console.sol";

// Interfaces
import { ILSP7DigitalAsset as ILSP7 } from "@lukso/lsp7-contracts/contracts/ILSP7DigitalAsset.sol";

// Modules
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";

// Libraries
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { TokenMessage } from "@hyperlane-xyz/core/contracts/token/libs/TokenMessage.sol";

// Constants
import { _TYPEID_LSP7_TOKENOPERATOR } from "@lukso/lsp7-contracts/contracts/LSP7Constants.sol";
import { _INTERFACEID_LSP1 } from "@lukso/lsp1-contracts/contracts/LSP1Constants.sol";

contract HypLSP7CollateralWithLSP1 is ERC165, TokenRouter {
    ILSP7 public immutable wrappedToken;

    /**
     * @notice Constructor
     * @param lsp7_ Address of the token to keep as collateral
     */
    constructor(address lsp7_, address mailbox_) TokenRouter(mailbox_) {
        require(Address.isContract(lsp7_), "HypLSP7Collateral: invalid token");
        wrappedToken = ILSP7(lsp7_);
    }

    function initialize(address _hook, address _interchainSecurityModule, address _owner) public virtual initializer {
        _MailboxClient_initialize(_hook, _interchainSecurityModule, _owner);
    }

    /**
     * @param typeId TypeId related to performing a bridge operation
     * @param data The `lsp1Data` sent by the function `authorizeOperator(address,uint256,bytes)` when the internal hook
     * below was triggered:
     *
     * User --> calls `authorizeOperator(...)` on LSP7 token to bridge with parameters:
     *  | address: router contract
     *  | uint256: amount to bridge
     *  | bytes: operatorNotificationData -> abi-encoded function call of `transferRemote(uint32 _destination, bytes32
     * _recipient, uint256 _amountOrId)`
     *  V
     *
     * Triggered internally by the function `_notifyTokenOperator(...)` with lsp1Data
     *
     * ```
     * abi.encode(address msg.sender (user), uint256 amount, bytes memory operatorNotificationData)
     * ```
     *
     * transferRemote(uint32,bytes32,uint256) selector -> 0x81b4e8b4
     *
     * Tokens that authorize and dont call the universalReceiver on authorization, will get front-runned
     */
    function universalReceiver(bytes32 typeId, bytes calldata data) public payable returns (bytes memory) {
        if (typeId == _TYPEID_LSP7_TOKENOPERATOR) {
            // 0x000000000000000000000000328809bc894f92807417d2dad6b7c998c1afdac6 -> msg.sender
            //   0000000000000000000000000000000000000000000000056bc75e2d63100000 -> authorized amount (100 with 18 decimals in hex)
            //   0000000000000000000000000000000000000000000000000000000000000060 -> operatorNotificationData
            //   0000000000000000000000000000000000000000000000000000000000000064
            //   81b4e8b4                                                         -> transferRemote(uint32,bytes32,uint256) selector
            //   000000000000000000000000000000000000000000000000000000000000000c -> destination (= chainId, here 12 in hex)
            //   0000000000000000000000001d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e -> recipient address
            //   0000000000000000000000000000000000000000000000056bc75e2d63100000 -> amount to transfer (100 with 18 decimals in hex)
            //   00000000000000000000000000000000000000000000000000000000         -> remaining padded to do 32 bytes words

            // `authorizeOperator(address,uint256,bytes)` calldata (example)
            // --------------------
            // The `lsp1Data` sent by `authorizeOperator(...)` contains 3 arguments:
            // - address: msg.sender (user) -> 32 bytes
            // - uint256: amount authorized -> 32 bytes
            // - bytes: operatorNotificationData -> which contains the encoded transferRemote(...) parameters
            address from = address(uint160(uint256(bytes32(data[:32]))));

            // if no data then revert
            if (uint256(bytes32(data[96:128])) == 0) revert("Authorization and Bridge must happen in the same tx");

            // Get the function selector (first 4 bytes after the offset + length)
            bytes4 executeSelectorToRun = bytes4(data[128:132]);

            // For transferRemote, we expect the following parameters (32 bytes each as abi-encoded:
            uint32 destination = uint32(uint256(bytes32(data[132:164])));
            bytes32 recipient = bytes32(data[164:196]);
            uint256 amount = uint256(bytes32(data[196:228]));

            console.log("destination: ", destination);
            console.logBytes32(recipient);
            console.log("amount: ", amount);
            console.log("msg.value: ", msg.value);

            // Check if it's a transferRemote call (0x81b4e8b4)
            if (executeSelectorToRun == 0x81b4e8b4) {
                require(msg.sender == address(wrappedToken), "transferRemote only possible from wrappedToken");

                // Normally we should use:
                // _transferRemote(
                //     destination,
                //     recipient,
                //     amount,
                //     0 // default value for _gasAmount
                // );

                // But `_transferRemote(...)` uses `msg.sender` as the `from` to transfer tokens.
                // Since we are dealing with a `universalReceiver(...)` callback on the HypLSP7Collateral contract
                // triggered via the `<LSP7 token>.authorizeOperator(...)`, the `msg.sender` is the token contract, which shouldn't be.
                // Therefore, we need to re-write the logic of the `_transferRemote(...)` to use the `from` extracted from the received `operatorNotificationData`
                wrappedToken.transfer(from, address(this), amount, true, "");

                bytes memory _tokenMessage = TokenMessage.format(recipient, amount, ""); // no token metadata

                // normally _transferRemote returns the message ID. We don't return it here (could be a problem for external contracts that interact with it and need it)
                /* messageId = */
                _Router_dispatch(
                    destination, msg.value, _tokenMessage, _GasRouter_hookMetadata(destination), address(hook)
                );

                emit SentTransferRemote(destination, recipient, amount);
            } else {
                revert("Invalid selector");
            }

            // making sure that there are no authorized amount left over and send it back to owner if that is the case
            uint256 remainingAuthorizedAmount = ILSP7(msg.sender).authorizedAmountFor(address(this), from);
            console.log("remainingAuthorizedAmount: ", remainingAuthorizedAmount);
            if (remainingAuthorizedAmount != 0) {
                ILSP7(msg.sender).transfer(from, address(this), remainingAuthorizedAmount, true, "");
                uint256 remainingBalance = ILSP7(msg.sender).balanceOf(address(this));
                ILSP7(msg.sender).transfer(address(this), from, remainingBalance, true, "");
            }
        }
        return abi.encodePacked(true);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == _INTERFACEID_LSP1 || super.supportsInterface(interfaceId);
    }

    function balanceOf(address _account) external view override returns (uint256) {
        return wrappedToken.balanceOf(_account);
    }

    /**
     * @dev Transfers `_amount` of `wrappedToken` from `msg.sender` to this contract.
     * @inheritdoc TokenRouter
     */
    function _transferFromSender(uint256 _amount) internal virtual override returns (bytes memory) {
        wrappedToken.transfer(msg.sender, address(this), _amount, true, "");
        return bytes(""); // no metadata
    }

    /**
     * @dev Transfers `_amount` of `wrappedToken` from this contract to `_recipient`.
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
        wrappedToken.transfer(address(this), _recipient, _amount, true, "");
    }
}
