# Contributing to LSP7 and LSP8 Token Routers for Hyperlane

First off, thank you for considering contributing! It's people like you that make this project such a great tool. Here are some guidelines to help you get started.

## How Can I Contribute?

1. [**Report Bugs**](https://github.com/lukso-network/lsp-bridge-HypLSP7/issues): Use the issue tracker to report bugs or suggest improvements.
2. [**Submit Pull Requests**](https://github.com/lukso-network/lsp-bridge-HypLSP7/pulls): If you have a fix or new feature, submit a pull request.
3. **Improve Documentation**: Help us make our README and docs better by fixing typos or adding more examples.

## Setting Up Your Environment

1. Fork the repository and clone it locally:
   ```sh
   git clone https://github.com/your-username/lsp-bridge-HypLSP7.git
   ```
2. Install dependencies:
   ```sh
   bun install
   ```
3. Make your changes, then run tests to ensure everything is working:
   ```sh
   forge test
   ```

## Code Style

We use Solhint and Prettier for code linting and formatting. Before submitting a pull request, make sure your code passes these checks:

```sh
bun run lint
forge fmt
```

## Commit Messages

Please follow this format when writing commit messages:

```
type(!): subject

body (optional)
```

Learn more about conventional commits and their prefixes in [RELEASE.md/#conventional-commit-prefixes](./RELEASE.md#conventional-commit-prefixes).

Types can be:

- `feat`: A new feature. Example: `feat: add native token transfer support`
- `fix`: A bug fix. Example: `fix: resolve contract initialization issue`
- `docs`: Documentation changes. Example: `docs: update README with setup instructions`
- `style`: Changes that do not affect the meaning of the code. Example: `style: format codebase using Prettier`
- `refactor`: Code refactoring. Example: `refactor: optimize token transfer function`
- `test`: Adding or refining tests. Example: `test: add unit tests for LSP7 contract`

Breaking changes should include a `!` before the type:

- `feat!`: A new feature that is a breaking change. Example: `feat!: remove deprecated API endpoint`
- `fix!`: A bug fix that requires user code changes. Example: `fix!: update parameter type for transfer function`

## Pull Requests

1. Make sure you are working on the latest version by rebasing your branch:
   ```sh
   git fetch origin
   git rebase origin/main
   ```
2. Submit a pull request with a clear description of your changes and why they are necessary.
3. Be prepared to update your pull request based on feedback from reviewers.

## License

By contributing, you agree that your contributions will be licensed under the MIT license.

Thank you for your contributions!
