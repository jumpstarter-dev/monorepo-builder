# Patches Directory

This directory contains source files that replace or supplement files from the upstream repositories when building the monorepo.

## Files

### `setup-e2e.sh`
- **Destination:** `monorepo/e2e/setup-e2e.sh`
- **Purpose:** One-time setup for e2e testing environment (not in upstream)
- **Usage:** `make e2e-setup` or `bash e2e/setup-e2e.sh`
- **Features:**
  - Installs dependencies (uv, Python, bats)
  - Auto-detects and installs bats helper libraries on macOS
  - Deploys dex with nip.io hostname (no /etc/hosts modification needed)
  - Deploys controller
  - Installs Jumpstarter packages
  - Creates setup marker file for run script

### `run-e2e.sh`
- **Destination:** `monorepo/e2e/run-e2e.sh`
- **Purpose:** Run e2e tests (after setup) or full setup+run in CI (not in upstream)
- **Usage:** `make e2e` or `make e2e-run` or `bash e2e/run-e2e.sh`
- **Features:**
  - Checks setup was completed
  - Runs bats test suite quickly
  - Supports `--full` flag for complete setup+run cycle
  - Works in CI and local development

## Cleanup

### `make e2e-clean`
- **Purpose:** Clean up the entire e2e test environment
- **Actions:**
  - Deletes the jumpstarter kind cluster
  - Removes generated certificates (ca.pem, server.pem, etc.)
  - Removes virtual environment (.venv)
  - Removes setup marker file
  - Cleans exporter configs from /etc/jumpstarter/exporters

## How Patches Are Applied

The `build-monorepo.sh` script applies these patches during the monorepo build:

1. `setup_github_actions()` - Removes upstream `e2e/action.yml` (e2e workflow uses make targets directly)
2. `copy_e2e_scripts()` - Copies `setup-e2e.sh` and `run-e2e.sh` to the e2e directory
3. `fix_e2e_dex_config()` - Updates upstream e2e files to use dex.127.0.0.1.nip.io:
   - `e2e/dex-csr.json` - Adds nip.io hostname to certificate
   - `e2e/dex.values.yaml` - Updates issuer URL
   - `e2e/tests.bats` - Updates all login commands and replaces `$GITHUB_ACTION_PATH` with `e2e`

## Adding New Patches

To add a new patch file:

1. Create the file in this directory
2. Add a copy command in `build-monorepo.sh` (in an appropriate function or create a new one)
3. Call the function in `main()` before `finalize_monorepo()`
4. Update this README
5. Run `make build` to test

## Editing Existing Patches

To modify an existing patch:

1. Edit the file in this directory (NOT in `monorepo/`)
2. Run `make build` to regenerate the monorepo
3. Test your changes in `monorepo/`

Remember: The `monorepo/` directory is regenerated from scratch on every build, so changes made there will be lost.
