# Hyperlane LSP7 version - `HypLSP7` [![Open in Gitpod][gitpod-badge]][gitpod] [![Github Actions][gha-badge]][gha] [![Foundry][foundry-badge]][foundry] [![License: MIT][license-badge]][license]

[gitpod]: https://gitpod.io/#https://github.com/lukso-network/lsp-bridge-HypLSP7
[gitpod-badge]: https://img.shields.io/badge/Gitpod-Open%20in%20Gitpod-FFB45B?logo=gitpod
[gha]: https://github.com/lukso-network/lsp-bridge-HypLSP7/actions
[gha-badge]: https://github.com/lukso-network/lsp-bridge-HypLSP7/actions/workflows/ci.yml/badge.svg
[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg
[license]: https://opensource.org/licenses/MIT
[license-badge]: https://img.shields.io/badge/License-MIT-blue.svg

This repo is the LSP7 version of the [`HypERC20`] and [`HypERC20Collateral`] of `@hyperlane-xyz/core` package. They are used to bridge tokens between the Ethereum and LUKSO chains using the [Hashi Bridge](https://crosschain-alliance.gitbook.io/hashi).

For more details on the **architecture and bridging flow**, see the [**`docs/`**](./docs/README.md) folder.

### Examples of bridged tokens

- ETH -> LUKSO: https://explorer.hyperlane.xyz/message/0x53a383e32fdb68748c8af5c86be3669e58eadc377db2a9f420826cb9474dd55c

- LUKSO -> ETH: https://explorer.hyperlane.xyz/message/0xf9c86a22e7b5584fc87a9d4ffc39f967a8745cd28b98ed2eaeb220c43996c4ca


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

This repository uses pre-configured GitHub Actions. The contracts are linted and tested on every push and pull requests. You can edit the CI script in [.github/workflows/ci.yml](./.github/workflows/ci.yml).


## Foundry Resources

This template builds upon the frameworks and libraries mentioned above, so please consult their respective documentation for details about their specific features.

For example, if you're interested in exploring Foundry in more detail, you should look at the
[Foundry Book](https://book.getfoundry.sh/). In particular, you may be interested in reading the
[Writing Tests](https://book.getfoundry.sh/forge/writing-tests.html) tutorial.


[`HypERC20Collateral`]: https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/%40hyperlane-xyz/core%405.2.0/solidity/contracts/token/HypERC20Collateral.sol
[`HypERC20`]: https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/%40hyperlane-xyz/core%405.2.0/solidity/contracts/token/HypERC20.sol
[`Mailbox`]: https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/%40hyperlane-xyz/core%405.2.0/solidity/contracts/Mailbox.sol
