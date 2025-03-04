# `HypERC20`

## Destination Gas

**Getter:**

- `destinationGas(uint32)` = param is the chain ID

**Setter:**

- `setDestinationGas(uint32,uint256)`
- `setDestinationGas(uint32[],uint256[])`

## Domains & Mailbox

**Getter:**

- `domains()`
- `localDomain()`
- `mailbox()`

## Routers

**Getter:**

- `routers(uint32)`

**Setter**

- `enrollRemoteRouter(uint32,bytes32)` (chain ID + destination of wrapper / collateral contract (abi-encoded))
- `enrollRemoteRouters(uint32[],bytes32[])`
- `unenrollRemoteRouter(uint32)`
- `unenrollRemoteRouters(uint32[])`

## Hooks

**Getter:**

- `hook()`

**Setter:**

- `setHook(address)`

## ISM

**Getter:**

- `interchainSecurityModule()`

**Setter:**

- `setInterchainSecurityModule(address)`

## Transferring functionalities

`quoteGasPayment(uint32)`

`transferRemote(uint32,bytes32,uint256)` = for bridging tokens, trigger the transfer from the source chain

- `uint32` = domain (chain ID)
- `bytes32` = recipient on destination chain
- `uint256` = amount

`transferRemote(unit32,bytes32,uint256,bytes,address)` = same as above with extra parameters

- `bytes` = hook metadata
- `address` = hook contract address

`handle(...)` = for receiving the bridged tokens on the destination chain
