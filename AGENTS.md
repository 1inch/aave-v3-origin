# AGENTS.md

## Cursor Cloud specific instructions

This repo is **Aave V3 Origin** — a Foundry-based Solidity smart-contract codebase. There is **no web server, database, API, or other long-running service**. "Running the application" means compiling the contracts and running the Foundry test suite against Foundry's built-in in-memory EVM. There is nothing to start as a daemon.

### Toolchain / environment

- `forge` (Foundry) is installed at `~/.foundry/bin` and is on `PATH` via `~/.bashrc` (installed with `foundryup`, currently v1.7.x). If `forge` is ever missing in a non-login shell, run `export PATH="$HOME/.foundry/bin:$PATH"`.
- Solidity dependencies are **git submodules** (`lib/forge-std`, `lib/solidity-utils`, plus nested OpenZeppelin modules). They must be initialized (`git submodule update --init --recursive`); the startup update script handles this. Builds fail with missing-import errors if they are absent.
- Node/npm deps (`npm install`) are only needed for `prettier` (lint) and `changesets` (release) — not for compiling or testing contracts.
- Fuzzing toolchain is installed in `~/.local/bin` (on `PATH` via `~/.bashrc`): `echidna` (v2.3.x), `medusa` (v1.5.x), plus `crytic-compile` and `solc-select` (with `solc 0.8.27` selected globally, matching `foundry.toml`). Both fuzzers compile through `crytic-compile`, which auto-detects the Foundry project and runs `forge build` under the hood. If they are missing in a non-login shell, run `export PATH="$HOME/.local/bin:$PATH"` (and `solc-select use 0.8.27` if `solc` resolves to the wrong version).

### Common commands (see `Makefile`, `foundry.toml`, `package.json`)

- Build: `forge build`
- Test (standard): `make test` (= `forge test -vvv --no-match-contract DeploymentsGasLimits`). Plain `forge test --no-match-contract DeploymentsGasLimits` is faster/quieter. The `DeploymentsGasLimits` suite is intentionally excluded from the standard run (gas-snapshot assertions).
- Single contract: `make test-contract filter=<ContractName>`
- Lint: `npm run lint` (prettier check); `npm run lint:fix` to auto-format.
- Coverage: `make coverage` (needs `lcov`/`genhtml`).
- 1inch Earn tests: `make test-1inch-earn` (forge unit/e2e + mainnet-fork when `RPC_MAINNET` is set). `make test-1inch-earn-anvil` runs the 17-stage Anvil integration harness (`tests/1inch-earn/anvil/run-anvil-integration.sh`): the real deploy scripts + live runtime scenarios via `cast`, including real-token multi-asset flows.

### Anvil integration harness conventions (`tests/1inch-earn/anvil/`)

- **Fund real ERC20s with `deal_erc20 <token> <holder> <rawAmt>`** — the cast equivalent of forge's `deal`. It auto-detects the `balanceOf` mapping slot by probing base slots 0..30 and writes via `anvil_setStorageAt` (verified for WETH slot 3 / WBTC+wstETH slot 0 / USDT slot 2 / USDC+cbBTC slot 9). Use this instead of hunting for mainnet whales, whose balances drift and break reruns. `ensure_supply_weth` wraps real ETH (so WETH9 stays ETH-backed for gateway unwraps).
- **Determinism on multiplexed public RPCs** (default `ethereum-rpc.publicnode.com`): the harness pins ~32 blocks behind HEAD (`FORK_BLOCK=<n>` to override), sends every pool action with an explicit `--gas-limit` so `cast` SKIPS the estimation `eth_call` (that estimation is what transiently reverts on a cold fork read), and gates progression on **index-immune `scaledBalanceOf`** reads (never `balanceOf`, which multiplies by a lazily-fetched reserve index that can read 0) with a mine+poll retry via the `ensure_*` helpers. Expect-revert checks deliberately keep estimation (no `--gas-limit`). A dedicated single-node RPC removes all nondeterminism.
- When adding a scenario: reuse `ensure_supply`/`ensure_supply_weth`/`ensure_borrow`/`ensure_debt_cleared`/`ensure_withdrawn` (idempotent, effect-gated) rather than raw `cast send`, and assert with `bn_*`/`sbal`/`bal` helpers. Anvil default accounts #0..#9 are the available signers (#0 is the deployer/KYC owner).
- Stateful fuzzing (invariants): `make echidna` / `make medusa`. These run **indefinitely** by design (`echidna_config.yaml` `testLimit: 20000000`; `medusa.json` `timeout: 0`), so run them in a background/tmux session and stop them manually. See the fuzzing gotcha below before relying on them.

### Agent skills

- Reusable agent skills are installed under `.agents/skills/` (via `npx skills`, tracked in `skills-lock.json`) and indexed by the always-on Cursor rule `.cursor/rules/agent-skills.mdc`. Load the relevant `SKILL.md` when its trigger matches: `solidity-auditor` (whole-file/repo security review), `differential-review` (security review of a PR/diff), `entry-point-analyzer` (entry-point / access-control mapping), `token-integration-analyzer` (token listing / weird-token checks), `fp-check` (verify a suspected finding), `variant-analysis` (hunt variants of a confirmed bug), `x-ray` (pre-audit readiness report), `fizz` (Echidna/Medusa invariant suites — note it may add a `[profile.fuzz]` block to `foundry.toml`), `upgrade-solidity-contracts` (proxy/upgrade/storage-layout work), `develop-secure-contracts` and `setup-solidity-contracts` (OpenZeppelin integration/setup).
- Manage with `npx skills list` / `npx skills update`.

### Non-obvious gotchas

- Running the test suite writes generated JSON files into `reports/` (Foundry `fs_permissions` grant read-write there). These are gitignored test artifacts and are also excluded from `npm run lint` via `.prettierignore` (as are the vendored skills under `.agents/`), so `npm run lint` is clean on a fresh checkout and after test runs.
- The default `forge test` run needs **no `.env` and no network**. `.env` RPC endpoints (see `.env.example`) are only for fork tests and deployment scripts; deployment additionally requires a Ledger.
- `echidna`/`medusa` are installed (see Toolchain), but `make echidna` and `make medusa` currently **fail on the committed configs due to pre-existing config/source drift**, not a tooling problem: both `tests/invariants/_config/echidna_config.yaml` and `medusa.json` still declare a predeployed `EModeLogic` library (`0xf09`), but `EModeLogic` no longer exists in `src/` (e-mode logic was refactored into other libraries). Symptoms after a successful ~15s `crytic-compile`/`forge build`: echidna prints `Given contract "EModeLogic" not found in given file`; medusa prints `EModeLogic was specified in the predeployed contracts but was not found in the compilation artifacts`. The binaries themselves are verified working on a standalone harness. Fixing the campaigns requires updating those config files (out of scope for env setup).
- `slither` is **not** installed; both fuzzers emit a non-fatal warning and continue without it. `Certora` is also not installed. Installing `slither` (`pip3 install --user slither-analyzer`) is optional and only improves fuzzing effectiveness.
