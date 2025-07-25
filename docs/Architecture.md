# Architecture Overview

This document provides an overview of the system architecture, explaining how different components interact with each
other.

## High-Level Components

The system is composed of several high-level components:

1. **Hyperlane Smart Contracts**: The core smart contracts that facilitate cross-chain communication.
2. **Mailbox**: A central component for relaying messages between chains.
3. **Relayer**: An off-chain service that listens to events on one chain and relays them to another chain.
4. **Interchain Security Module (ISM)**: Ensures the security of cross-chain transactions by validating message
   signatures.

## Hyperlane Smart Contracts

The Hyperlane smart contracts are designed to facilitate cross-chain communication. They include:

- `HypERC20`: An ERC20 token with remote transfer functionality.
- `HypLSP7`: An LSP7 token with remote transfer functionality.
- `HypERC20Collateral`: An ERC20 token with collateral functionality for cross-chain operations.
- `HypLSP7Collateral`: An LSP7 token with collateral functionality for cross-chain operations.
- `Mailbox`: A contract that receives messages from the relayer and processes them.

## Mailbox

The Mailbox is a central component in the Hyperlane architecture. It acts as an intermediary between the source chain
and the destination chain. The Mailbox listens for events on the source chain, validates them, and then forwards them to
the destination chain.

## Relayer

The Relayer is an off-chain service that listens to events on one chain and relays them to another chain. It plays a
crucial role in ensuring that messages are delivered across chains.

## Interchain Security Module (ISM)

The ISM ensures the security of cross-chain transactions by validating message signatures. It checks that messages are
signed by a sufficient number of validators before they are processed.

## Interaction Flow

1. **User Action**: The user initiates a transaction on the source chain, such as transferring tokens.
2. **Smart Contract Execution**: The smart contract on the source chain locks the tokens and emits an event.
3. **Event Listening**: The Relayer listens for this event and retrieves the message from the Mailbox.
4. **Message Relaying**: The Relayer forwards the message to the destination chain's Mailbox.
5. **Validation**: The ISM validates the message signature to ensure its authenticity.
6. **Token Minting/Unlocking**: If the message is valid, the destination chain's smart contract mints or unlocks the
   corresponding tokens.

## Detailed Component Interactions

### Ethereum -> LUKSO

1. **User Approval**: The user approves the `HypERC20Collateral` contract to spend a certain amount of ERC20 tokens.
   ```solidity
   HypERC20.approve(address spender, uint256 amount)
   ```
2. **Token Locking**: The user calls `transferRemote(...)` on the `HypERC20Collateral` contract to lock the tokens and
   emit an event.
   ```solidity
   transferRemote(
       uint32 destination, // chain ID
       address recipient,
       uint256 amount
   )
   ```
3. **Event Emission**: The smart contract emits an event that is picked up by the Relayer.

### LUKSO -> Ethereum

1. **Token Burning**: The user calls `transferRemote(...)` on the `HypLSP7` contract to burn the tokens and emit an
   event.
   ```solidity
   transferRemote(
       uint32 destination, // chain ID
       address recipient,
       uint256 amount
   )
   ```
2. **Event Emission**: The smart contract emits an event that is picked up by the Relayer.

## Conclusion

This architecture overview provides a high-level understanding of how the different components interact to facilitate
cross-chain communication. For more detailed information, refer to the specific documentation for each component.
