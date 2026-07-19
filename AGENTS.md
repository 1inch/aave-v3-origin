# AGENTS.md

## Cursor Cloud specific instructions

This repo is **Aave V3 Origin** — a Foundry-based Solidity smart-contract codebase. There is **no web server, database, API, or other long-running service**. "Running the application" means compiling the contracts and running the Foundry test suite against Foundry's built-in in-memory EVM. There is nothing to start as a daemon.

### Toolchain / environment

- `forge` (Foundry) is installed at `~/.foundry/bin` and is on `PATH` via `~/.bashrc` (installed with `foundryup`, currently v1.7.x). If `forge` is ever missing in a non-login shell, run `export PATH="$HOME/.foundry/bin:$PATH"`.
- Solidity dependencies are **git submodules** (`lib/forge-std`, `lib/solidity-utils`, plus nested OpenZeppelin modules). They must be initialized (`git submodule update --init --recursive`); the startup update script handles this. Builds fail with missing-import errors if they are absent.
- Node/npm deps (`npm install`) are only needed for `prettier` (lint) and `changesets` (release) — not for compiling or testing contracts.

### Common commands (see `Makefile`, `foundry.toml`, `package.json`)

- Build: `forge build`
- Test (standard): `make test` (= `forge test -vvv --no-match-contract DeploymentsGasLimits`). Plain `forge test --no-match-contract DeploymentsGasLimits` is faster/quieter. The `DeploymentsGasLimits` suite is intentionally excluded from the standard run (gas-snapshot assertions).
- Single contract: `make test-contract filter=<ContractName>`
- Lint: `npm run lint` (prettier check); `npm run lint:fix` to auto-format.
- Coverage: `make coverage` (needs `lcov`/`genhtml`).

### Agent skills

- Reusable agent skills are installed under `.agents/skills/` (via `npx skills`, tracked in `skills-lock.json`) and indexed by the always-on Cursor rule `.cursor/rules/agent-skills.mdc`. Load the relevant `SKILL.md` when its trigger matches: `solidity-auditor` (whole-file/repo security review), `differential-review` (security review of a PR/diff), `entry-point-analyzer` (entry-point / access-control mapping), `token-integration-analyzer` (token listing / weird-token checks), `fp-check` (verify a suspected finding), `variant-analysis` (hunt variants of a confirmed bug), `x-ray` (pre-audit readiness report), `fizz` (Echidna/Medusa invariant suites — note it may add a `[profile.fuzz]` block to `foundry.toml`), `upgrade-solidity-contracts` (proxy/upgrade/storage-layout work), `develop-secure-contracts` and `setup-solidity-contracts` (OpenZeppelin integration/setup).
- Manage with `npx skills list` / `npx skills update`.

### Non-obvious gotchas

- Running the test suite writes generated JSON files into `reports/` (Foundry `fs_permissions` grant read-write there). These are gitignored test artifacts and are also excluded from `npm run lint` via `.prettierignore`.
- The default `forge test` run needs **no `.env` and no network**. `.env` RPC endpoints (see `.env.example`) are only for fork tests and deployment scripts; deployment additionally requires a Ledger.
- Optional fuzzing/verification tools (Echidna, Medusa, Certora) are **not** installed by default and are not part of the normal build/test loop.
