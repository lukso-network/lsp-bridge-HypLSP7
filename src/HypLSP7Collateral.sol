// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

// Interfaces
import { ILSP7DigitalAsset as ILSP7 } from "@lukso/lsp7-contracts/contracts/ILSP7DigitalAsset.sol";

// Modules
import { TokenRouter } from "@hyperlane-xyz/core/contracts/token/libs/TokenRouter.sol";

contract HypLSP7Collateral is TokenRouter {
    ILSP7 public immutable wrappedToken;

    /**
     * @notice Constructor
     * @param lsp7_ Address of the token to keep as collateral
     */
    constructor(address lsp7_, address mailbox_) TokenRouter(mailbox_) {
        wrappedToken = ILSP7(lsp7_);
    }

    function initialize(address _hook, address _interchainSecurityModule, address _owner) public virtual initializer {
        _MailboxClient_initialize(_hook, _interchainSecurityModule, _owner);
    }


      /**
     * @param typeId TypeId related to performing a bridge operation
     * @param data The `lsp1Data` sent by the function `authorizeOperator(address,uint256,bytes)` when the internal hook below was triggered:
     *
     * User --> calls `authorizeOperator(...)` on LSP7 token to bridge with parameters:
     *  | address: router contract
     *  | uint256: amount to bridge
     *  | bytes: operatorNotificationData -> abi-encoded function call of `transferRemote(uint32 _destination, bytes32 _recipient, uint256 _amountOrId)`
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
    function universalReceiver(bytes32 typeId, bytes calldata data) public returns (bytes memory) {
        if (typeId == 0x386072cc5a58e61263b434c722725f21031cd06e7c552cfaa06db5de8a320dbc) {
            // `authorizeOperator(address,uint256,bytes)` calldata (example)
            // --------------------
            address from = address(uint160(uint256(bytes32(data[:32]))));

            // The `lsp1Data` sent by `authorizeOperator(...)` contains 3 arguments:
            // - address: msg.sender (user) -> 32 bytes
            // - uint256: amount authorize -> 32 bytes
            // - bytes: operatorNotificationData -> which contains the encoded transferRemote parameters

            // if no data then revert
            if (uint256(bytes32(data[96:128])) == 0) revert("Authorization and Bridge must happen in the same tx");

            // Get the function selector (first 4 bytes after the offset)
            bytes4 executeSelectorToRun = bytes4(data[128:132]);

            // For transferRemote, we expect the following parameters:
            // - uint32 _destination (4 bytes)
            // - bytes32 _recipient (32 bytes)
            // - uint256 _amountOrId (32 bytes)
            uint32 destination = uint32(bytes4(data[132:136]));
            bytes32 recipient = bytes32(data[136:168]);
            uint256 amount = uint256(bytes32(data[168:200]));

            // Check if it's a transferRemote call (0x81b4e8b4)
            if (executeSelectorToRun == 0x81b4e8b4) {
                _transferRemote(
                    destination,
                    recipient,
                    amount,
                    0  // default value for _gasAmount
                );
            } else {
                revert("Invalid selector");
            }

            // making sure that there are no authorized amount left over and send it back to owner if that is the case
            uint256 remainingAuthorizedAmount = ILSP7(msg.sender).authorizedAmountFor(address(this), from);
            if(remainingAuthorizedAmount != 0) {
                ILSP7(msg.sender).transfer(from, address(this), remainingAuthorizedAmount, true, "");
                uint256 remainingBalance = ILSP7(msg.sender).balanceOf(address(this));
                ILSP7(msg.sender).transfer(address(this), from, remainingBalance, true, "");
            }
        }
        return abi.encodePacked(true);
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
