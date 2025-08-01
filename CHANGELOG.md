# Changelog

## 0.1.0 (2025-08-01)


### ⚠ BREAKING CHANGES

* disable minting feature on `initialize(...)` for `HypLSP7` and `HypLSP8`
* change `Freezable` contract to `PausableController` + define `address(0)` as "revoked forever"
* remove setting data keys / values on `initialize(...)`
* upgrade Hyperlane dependencies to v8 and latest LSP smart contracts

### refactor

* change `Freezable` contract to `PausableController` + define `address(0)` as "revoked forever" ([1ec05a2](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/1ec05a21ba8918408499e4082812ae587f8f4758))
* disable minting feature on `initialize(...)` for `HypLSP7` and `HypLSP8` ([f434799](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/f4347993b31c02a460cbcddd1b3a09c0d3412e72))
* remove setting data keys / values on `initialize(...)` ([ea28c90](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/ea28c9016f6c319f45be20d2658dc93c69a52965))
* upgrade Hyperlane dependencies to v8 and latest LSP smart contracts ([5da4aaa](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/5da4aaa479f702f1e84ed531a4f7c20e1a06967e))


### Features

* add `_lsp4Metadata` parameter in `initialize(...)` function ([3dc1649](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/3dc1649e69102ffceb6ca6c71d05a5e3d03805d6))
* add first iteration of `HypLSP7.sol` ([66de491](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/66de491fa4d83260867214e02a520996ea678a8f))
* add init `dataKeys` & `dataValues` ([05440ad](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/05440ad53601c60669669b193c7b95f49c40d0d1))
* add universalReceiver to HypLSP7Collateral ([e1d760b](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/e1d760b0518845c34fa516d0d0a792c0ba843226))
* added tests for pausing for LSP8 ([81095e2](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/81095e27fa910caaa1760180df40dc967ec53d24))
* create `HypERC721ForLSP8` ([7ed5a12](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/7ed5a1212b1cd37acc3d6b6d18eaa7304522b1b1))
* create `HypLSP7Collateral` + adjusted version of `HypERC20` when bridging an LSP7 from LUKSO to Ethereum ([9b63dd3](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/9b63dd32fa2f7b22df64d29e4bfddd2feca7c520))
* create lsp8Mock ([34402b2](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/34402b2e6f8d98f9afba9d2efc0f8d06c8a1b0c8))
* create Pausable version of `HypLSP7`, `HypLSP7Collateral` and `HypNative` with `CircuitBreaker` in inheritance ([0a98254](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/0a9825440295c72a74d89572cb6c47b7b93c545b))
* create pausable version of HypERC20 ([b641db5](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/b641db595cc29b01645d064a6f892e51e67e7d8d))
* create pausable version of HypERC20Collateral ([79be37e](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/79be37ecb10ea2236a145ec681ea92a36e81065e))
* HypLSP8 implementation ([4ee4240](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/4ee424059a1cd27b37559c682786bc660da57347))
* initial commit ([791a9b8](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/791a9b815245877769d170a77bfb64ccb2dd960b))
* initial test for hypLSP8 ([752d76a](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/752d76a5ee48919b0ca0eb7ed9264f2c0f9a6167))
* PausableHook reverts remoteTransfer on origin chain to prevent loss of funds ([54e59a8](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/54e59a8e5b4addd32abaf515b346fa2891e549f5))


### Bug Fixes

* add contract existence check in `HypLSP8Collateral` ([ed800a3](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/ed800a35fa086b8c9ee67be14f683305a022c60a))
* add new function `authorizeTokenForBridge` in `HypLSP7Collateral` for LSP7 compatibility ([eb0244f](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/eb0244fa6210fac64ed599350d87518f7514f43e))
* lint errors ([c3a0e06](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/c3a0e06a0084a198a57b92e9a7f8c648a8eb0cab))
* linter ([4cfe413](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/4cfe41381884d8169e73461e7a90befe5c675ce2))
* lsp17 build error ([4de4028](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/4de4028be2571327ee108ecf68c1d8521471dc6b))
* solhint errors ([ffa2248](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/ffa22482526b8617de8d5d79cd8a1e7600a135fe))
* use correcct `LSP4TokenType` in `HypLSP8` ([20c29af](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/20c29afe9bc259d5aa6d145b45adc355ee6ab668))


### Miscellaneous

* add comment about `_mintAmount` param + fix solc compiler warnings ([8b8be7b](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/8b8be7bd210516c61ded639ca90becf89ab99994))
* cleanup more solhint errors and warnings ([f71fe66](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/f71fe666ee7aeada39a2385dae251a96524a6bb6))
* fix linter errors + use stricter rules ([77507a5](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/77507a5f53afc6515ca0f6de4bcb3fbb89bbaf9a))
* fix prettier ([cd85e4c](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/cd85e4c5af53e6d44f4ca4df61565f7cc0a5c5bd))
* fix release-please workflow ([1b72a17](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/1b72a1764504d1e090648f40dc3e056b01b431e2))
* init from https://github.com/PaulRBerg/foundry-template at 109802e ([67672c8](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/67672c83c7cdfb72301b81a3ba69592d0f03e4be))
* mark correct version of hyperlane dependency used ([76736d7](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/76736d724618cf348e712e02aac0a0a48e5d4a53))
* move `HypLSP7CollateralWithLSP1` contract to `Mocks` folder under `tests/` ([bb630c4](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/bb630c475ef3d0bc3b7ccbc6f70bdb0383bda3cc))
* remove `FUNDING.yml` ([6d4901f](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/6d4901fa05172c7d7f3771aeffdeb369027ec8e1))
* remove commented code ([a4bfbd5](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/a4bfbd5e2c605ebd800f19c4228d5bb7ac27454f))
* remove duplicate remapping + re-use already defined test variable ([bb2828c](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/bb2828c55bae99652e757da19aea956224cc6764))
* remove shell script `rename.sh` ([9f8e4a1](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/9f8e4a15d76b19ee56c565a4f64a0641f231bdb6))
* remove unused contracts + silent linter errors ([6d91639](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/6d916394747600c031f6c4740b20c077fa605686))
* remove unused images ([243e655](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/243e655b25934073f9eacd2521311f455093f5d7))
* update software license in Solidity files ([c93245b](https://github.com/lukso-network/lsp-bridge-HypLSP7/commit/c93245b0dcddb6caf6b964ab79d0c4559657feec))
