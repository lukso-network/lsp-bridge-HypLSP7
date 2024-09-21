# Hyperlane LSP7 version - `HypLSP7` [![Open in Gitpod][gitpod-badge]][gitpod] [![Github Actions][gha-badge]][gha] [![Foundry][foundry-badge]][foundry] [![License: MIT][license-badge]][license]

[gitpod]: https://gitpod.io/#https://github.com/lukso-network/lsp-bridge-HypLSP7
[gitpod-badge]: https://img.shields.io/badge/Gitpod-Open%20in%20Gitpod-FFB45B?logo=gitpod
[gha]: https://github.com/lukso-network/lsp-bridge-HypLSP7/actions
[gha-badge]: https://github.com/lukso-network/lsp-bridge-HypLSP7/actions/workflows/ci.yml/badge.svg
[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg
[license]: https://opensource.org/licenses/MIT
[license-badge]: https://img.shields.io/badge/License-MIT-blue.svg

## Architecture & Workflow

### Ethereun -> LUKSO

![Ethereum to LUKSO bridge flow](./assets/flow-ethereum-lukso-hashi-bridge.png)


**on Ethereum chain**

1. User transfer ERC20 token to Hyp Collateral contract. The token is locked in the collateral contract.
2. Hyp Collateral contract call `Mailbox` to pass the message.
3. `Mailbox` call Default Hook (created by Hyperlane) and Hashi Hook (created by CCIA team).
4. Hashi Hook dispatch the token relaying message from Yaho contracts.

**Off chain**

4. Hashi relayer (managed by CCIA team) will listen to event from Yaho contracts and request the reporter contracts to relay token relaying message.
5. Hashi executor (managed by CCIA team) will listen to event from each Hashi adapter contracts and call Yaru.executeMessages. This step will check whether the Hashi adapters agree on a specify message id (a threshold number of hash is stored), and set the message Id to verified status.
6. Validator (run by Hyperlane & LUKSO team) will sign the Merkle root when new dispatches happen in Mailbox.
7. Hyperlane relayer (run by Hyperlane team) relays the message by calling Mailbox.process().

**on LUKSO chain**

8. When `Mailbox.process()` is called, it will check with Multisig ISM (includes Hashi ISM), whether the message is signed by validators & verified by Hashi ISM. If so, it will mint hypERC20 token to the receiver.
9. For compatibility, LSP7 wrapper need to be created to mint LSP7 token to the user.

### LUKSO -> Ethereum

![LUKSO to Ethereum bridge flow](./assets/flow-lukso-ethereum-hashi-bridge.png)

**on LUKSO chain**

1. User transfer LSP7 token to HypERC20 contract and the token is burn.
2. HypERC20 contract call Mailbox to pass the message.
3. Mailbox call Default Hook (created by Hyperlane) and Hashi Hook (created by CCIA team).
4. Hashi Hook dispatch the token relaying message from Yaho contracts.

**Off chain**

4. Off chain process remains the same as before, except there is no Light Client support for Hashi from LUKSO → Ethereum.

**on Ethereum chain**

5. When `Mailbox.process()` is called, it will check with Multisig ISM (includes Hashi ISM), whether the message is signed by validators & verified by Hashi ISM. If so, it will unlock ERC20 token to the receiver.



### Examples of bridged tokens

- ETH -> LUKSO: https://explorer.hyperlane.xyz/message/0x53a383e32fdb68748c8af5c86be3669e58eadc377db2a9f420826cb9474dd55c

- LUKSO -> ETH: https://explorer.hyperlane.xyz/message/0xf9c86a22e7b5584fc87a9d4ffc39f967a8745cd28b98ed2eaeb220c43996c4ca


### Relevant links & resources

- [Architecture diagrams](https://hackmd.io/WXwzLS5TS4q_G3C7w2DkiA)

## Getting Started

This project is based on the Foundry template by PaulRBerg.

```sh
bun install # install Solhint, Prettier, and other Node.js deps
```

If this is your first time with Foundry, check out the
[installation](https://github.com/foundry-rs/foundry#installation) instructions.

### Installing Dependencies

Foundry typically uses git submodules to manage dependencies, but this template uses Node.js packages because
[submodules don't scale](https://twitter.com/PaulRBerg/status/1736695487057531328).

This is how to install dependencies:

1. Install the dependency using your preferred package manager, e.g. `bun install dependency-name`
   - Use this syntax to install from GitHub: `bun install github:username/repo-name`
2. Add a remapping for the dependency in [remappings.txt](./remappings.txt), e.g.
   `dependency-name=node_modules/dependency-name`

Note that OpenZeppelin Contracts is pre-installed, so you can follow that as an example.



### Sensible Defaults

This template comes with a set of sensible default configurations for you to use. These defaults can be found in the
following files:

```text
├── .editorconfig
├── .gitignore
├── .prettierignore
├── .prettierrc.yml
├── .solhint.json
├── foundry.toml
└── remappings.txt
```




## Usage

This is a list of the most frequently needed commands.

### Build & Compile


```sh
# Build the contracts:
forge build

# Delete the build artifacts and cache directories:
forge clean

# Get a test coverage report:
forge coverage

# Format the contracts:
forge fmt

# Get a gas report:
forge test --gas-report

# Lint the contracts:
bun run lint

# Run the tests:
forge test

# Generate test coverage and output result to the terminal:
bun run test:coverage

# Generate test coverage with lcov report (you'll have to open the `./coverage/index.html` file in your browser,
# to do so simply copy paste the path):
bun run test:coverage:report
```

### GitHub Actions

This repository uses pre-configured GitHub Actions. The contracts are linted and tested on every push and pull requests.

You can edit the CI script in [.github/workflows/ci.yml](./.github/workflows/ci.yml).


## Foundry Resources

This template builds upon the frameworks and libraries mentioned above, so please consult their respective documentation for details about their specific features.

For example, if you're interested in exploring Foundry in more detail, you should look at the
[Foundry Book](https://book.getfoundry.sh/). In particular, you may be interested in reading the
[Writing Tests](https://book.getfoundry.sh/forge/writing-tests.html) tutorial.
