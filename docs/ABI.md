# HypERC20 ABI Functions

This document provides a detailed overview of the `HypERC20` smart contract's ABI functions, including descriptions and
usage examples.

## Destination Gas

### Getter

- **Function**: `destinationGas(uint32)`
  - **Description**: Retrieves the gas limit for the specified chain ID.
  - **Parameters**:
    - `uint32`: Chain ID
  - **Example Usage**:
    ```solidity
    uint256 gasLimit = hypERC20.destinationGas(chainId);
    ```

### Setter

- **Function**: `setDestinationGas(uint32, uint256)`
  - **Description**: Sets the gas limit for a specific chain ID.
  - **Parameters**:
    - `uint32`: Chain ID
    - `uint256`: Gas limit value
  - **Example Usage**:
    ```solidity
    hypERC20.setDestinationGas(chainId, gasLimit);
    ```

- **Function**: `setDestinationGas(uint32[], uint256[])`
  - **Description**: Sets the gas limits for multiple chain IDs.
  - **Parameters**:
    - `uint32[]`: Array of chain IDs
    - `uint256[]`: Array of corresponding gas limit values
  - **Example Usage**:
    ```solidity
    uint32[] memory chainIds = new uint32[](2);
    uint256[] memory gasLimits = new uint256[](2);
    hypERC20.setDestinationGas(chainIds, gasLimits);
    ```

## Domains & Mailbox

### Getter

- **Function**: `domains()`
  - **Description**: Retrieves the list of domains.
  - **Example Usage**:
    ```solidity
    address[] memory domainList = hypERC20.domains();
    ```

- **Function**: `localDomain()`
  - **Description**: Retrieves the local domain address.
  - **Example Usage**:
    ```solidity
    address localDomainAddr = hypERC20.localDomain();
    ```

- **Function**: `mailbox()`
  - **Description**: Retrieves the mailbox address.
  - **Example Usage**:
    ```solidity
    address mailboxAddr = hypERC20.mailbox();
    ```

## Routers

### Getter

- **Function**: `routers(uint32)`
  - **Description**: Retrieves the router address for a specific chain ID.
  - **Parameters**:
    - `uint32`: Chain ID
  - **Example Usage**:
    ```solidity
    address routerAddr = hypERC20.routers(chainId);
    ```

### Setter

- **Function**: `enrollRemoteRouter(uint32, bytes32)`
  - **Description**: Registers a remote router for a specific chain ID.
  - **Parameters**:
    - `uint32`: Chain ID
    - `bytes32`: ABI-encoded destination of the wrapper/collateral contract
  - **Example Usage**:
    ```solidity
    address _address = 0x...
    bytes32 memory routerData = bytes32(abi.encode(_address));
    hypERC20.enrollRemoteRouter(chainId, routerData);
    ```

- **Function**: `enrollRemoteRouters(uint32[], bytes32[])`
  - **Description**: Registers multiple remote routers for specific chain IDs.
  - **Parameters**:
    - `uint32[]`: Array of chain IDs
    - `bytes32[]`: Array of corresponding ABI-encoded router data
  - **Example Usage**:
    ```solidity
    uint32[] memory chainIds = new uint32[](2);
    bytes32[] memory routerDataArray = new bytes32[](2);
    hypERC20.enrollRemoteRouters(chainIds, routerDataArray);
    ```

- **Function**: `unenrollRemoteRouter(uint32)`
  - **Description**: Unregisters a remote router for a specific chain ID.
  - **Parameters**:
    - `uint32`: Chain ID
  - **Example Usage**:
    ```solidity
    hypERC20.unenrollRemoteRouter(chainId);
    ```

- **Function**: `unenrollRemoteRouters(uint32[])`
  - **Description**: Unregisters multiple remote routers for specific chain IDs.
  - **Parameters**:
    - `uint32[]`: Array of chain IDs
  - **Example Usage**:
    ```solidity
    uint32[] memory chainIds = new uint32[](2);
    hypERC20.unenrollRemoteRouters(chainIds);
    ```

## Hooks

### Getter

- **Function**: `hook()`
  - **Description**: Retrieves the hook contract address.
  - **Example Usage**:
    ```solidity
    address hookAddr = hypERC20.hook();
    ```

### Setter

- **Function**: `setHook(address)`
  - **Description**: Sets the hook contract address.
  - **Parameters**:
    - `address`: Hook contract address
  - **Example Usage**:
    ```solidity
    hypERC20.setHook(newHookAddress);
    ```

## Interchain Security Module (ISM)

### Getter

- **Function**: `interchainSecurityModule()`
  - **Description**: Retrieves the ISM address.
  - **Example Usage**:
    ```solidity
    address ismAddr = hypERC20.interchainSecurityModule();
    ```

### Setter

- **Function**: `setInterchainSecurityModule(address)`
  - **Description**: Sets the ISM address.
  - **Parameters**:
    - `address`: ISM contract address
  - **Example Usage**:
    ```solidity
    hypERC20.setInterchainSecurityModule(newISMAddress);
    ```

## Transferring Functionality

### Quote Gas Payment

- **Function**: `quoteGasPayment(uint32)`
  - **Description**: Quotes the gas payment for a specific chain ID.
  - **Parameters**:
    - `uint32`: Chain ID
  - **Example Usage**:
    ```solidity
    uint256 quote = hypERC20.quoteGasPayment(chainId);
    ```

### Transfer Remote (Bridging Tokens)

- **Function**: `transferRemote(uint32, bytes32, uint256)`
  - **Description**: Initiates a token transfer from the source chain to another chain.
  - **Parameters**:
    - `uint32`: Destination domain (chain ID)
    - `bytes32`: Recipient address on destination chain
    - `uint256`: Amount of tokens to transfer
  - **Example Usage**:
    ```solidity
    hypERC20.transferRemote(destinationChainId, recipientAddress, amount);
    ```

- **Function**: `transferRemote(uint32, bytes32, uint256, bytes, address)`
  - **Description**: Initiates a token transfer with additional parameters.
  - **Parameters**:
    - `uint32`: Destination domain (chain ID)
    - `bytes32`: Recipient address on destination chain
    - `uint256`: Amount of tokens to transfer
    - `bytes`: Hook metadata
    - `address`: Hook contract address
  - **Example Usage**:
    ```solidity
    hypERC20.transferRemote(destinationChainId, recipientAddress, amount, hookMetadata, hookContract);
    ```

### Handle (Receiving Bridged Tokens)

- **Function**: `handle(...)`
  - **Description**: Processes the receipt of bridged tokens on the destination chain.
