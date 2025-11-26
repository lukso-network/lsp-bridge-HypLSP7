# LSP7 and LSP8 Token Routers for Hyperlane

[![Github Actions](https://github.com/lukso-network/lsp-bridge-HypLSP7/actions/workflows/ci.yml/badge.svg)](https://github.com/lukso-network/lsp-bridge-HypLSP7/actions)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://getfoundry.sh/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## Overview

This repository provides LSP7 and LSP8 compatible versions of Hyperlane's token routers, specifically adaptations of [`HypERC20`] and [`HypERC20Collateral`] for LSP7, and [`HypERC721`] and [`HypERC721Collateral`] for LSP8 from the [`@hyperlane-xyz/core`](https://www.npmjs.com/package/@hyperlane-xyz/core) contracts package. These contracts enable seamless token bridging across chains using the [Hyperlane protocol](https://docs.hyperlane.xyz).

For detailed architecture and bridging flow, refer to the [**documentation**](./docs/README.md).

## Features

- **LSP7 and LSP8 Compatibility**: Create Hyperlane synthetic tokens based on LUKSO's LSP token standards.
- **Hyperlane Integration**: Secure and efficient with support for Hyperlane Warp Routes (HWR) 2.0, enabling scaling, multi collateral routes and rebalancing.
- **Pausable Contracts**: Additional pausable versions for enhanced control.
- **WAGMI Typed ABIs**: Auto-generated typed ABIs generated with WAGMI.
- **Unit Tests**: Comprehensive test suite and CI integration.

## Examples of Bridged Tokens

- ETH -> LUKSO:
  [Hyperlane Explorer](https://explorer.hyperlane.xyz/message/0x53a383e32fdb68748c8af5c86be3669e58eadc377db2a9f420826cb9474dd55c)
- LUKSO -> ETH:
  [Hyperlane Explorer](https://explorer.hyperlane.xyz/message/0xf9c86a22e7b5584fc87a9d4ffc39f967a8745cd28b98ed2eaeb220c43996c4ca)

## Getting Started

This project is based on the Foundry template by PaulRBerg.

### Prerequisites

- [Foundry](https://getfoundry.sh/) installed.
- Node.js and Bun (or npm/yarn) for dependencies.

If this is your first time with Foundry, check out the [installation instructions](https://github.com/foundry-rs/foundry#installation).

### Installing Dependencies

Foundry typically uses git submodules, but this template uses Node.js packages for better scalability.

1. Install dependencies:

```sh
bun install
```

To add a new dependency:

1. Install using your package manager, e.g., `bun install dependency-name` (or from GitHub: `bun install github:username/repo-name`).
2. Add a remapping in [remappings.txt](./remappings.txt), e.g., `dependency-name=node_modules/dependency-name`.

Note: Only add the newly installed package to the remapping if:

- The new package exports Solidity files that we use.
- The dependency does not start with `@` (we already have `'@=node_modules/@'` in 'remappings.txt').

Note: OpenZeppelin Contracts is pre-installed as an example.

**Important:** This project uses OpenZeppelin v4.9.6 and is not yet compatible with OpenZeppelin v5.

### Sensible Defaults

This template includes sensible defaults in:

```
├── .editorconfig
├── .gitignore
├── .prettierignore
├── .prettierrc.yml
├── .solhint.json
├── foundry.toml
└── remappings.txt
```

## Usage

Common commands:

### Build & Compile

```sh
# Compile the contracts
bun run build

# Filter the generated artifacts
bun run build:artifacts

# Generate WAGMI typed ABIs
bun run build:wagmi

# Build the WAGMI typed ABIs
bun run build:js

# Build the NPM package for release
bun run build:package
```

### Clean the repository

```sh
# Delete build artifacts and cache
bun run clean
```

### Test the smart contracts

```sh
# Run the tests
bun run test

# Get gas report
bun run test:gas

# Generate test coverage output
bun run test:coverage

# Generate test coverage with lcov report (open ./coverage/index.html in browser)
bun run test:coverage:report
```

### Format the code

```sh
# Check if contracts are formatted
bun run prettier:check

# Format the contracts
bun run prettier:write

# Lint the contracts
bun run lint
```

### Get the package as `.tgz`

To obtain the package as a `.tgz` archive, follow these steps:

1. Build the package:

   ```sh
   bun run build:package
   ```

2. Package the built files into a `.tgz` archive:
   ```sh
   bun pm pack
   ```

## Audits

The security audits done in these smart contracts can be found under the [`audits/`](./audits/) folder.

## GitHub Actions

Pre-configured workflows lint and test on every push and pull request. Edit [.github/workflows/ci.yml](./.github/workflows/ci.yml) as needed.

## Documentation

For architecture, bridging flow, and ABI details, see the [docs/](./docs/README.md) folder.

## Foundry Resources

Consult the [Foundry Book](https://book.getfoundry.sh/) for details, especially the [Writing Tests tutorial](https://book.getfoundry.sh/forge/writing-tests.html).

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines on pull requests, code style, and testing.

## License

MIT License. See the [LICENSE.md](./LICENSE.md) file for details.

## References

[`HypERC20Collateral`]: https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/%40hyperlane-xyz/core%408.1.1/solidity/contracts/token/HypERC20Collateral.sol
[`HypERC20`]: https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/%40hyperlane-xyz/core%408.1.1/solidity/contracts/token/HypERC20.sol
[`HypERC721Collateral`]: https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/%40hyperlane-xyz/core%408.1.1/solidity/contracts/token/HypERC721Collateral.sol
[`HypERC721`]: https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/%40hyperlane-xyz/core%408.1.1/solidity/contracts/token/HypERC721.sol
[`Mailbox`]: https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/%40hyperlane-xyz/core%408.1.1/solidity/contracts/Mailbox.sol
