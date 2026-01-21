# Patches Directory

This directory contains source files that replace or supplement files from the upstream repositories when building the monorepo.

## Files

### `tests.bats`
- **Destination:** `monorepo/e2e/tests.bats`
- **Purpose:** Monorepo-adapted version of e2e test suite (replaces upstream)
- **Usage:** Run via `make e2e` or `bash e2e/run-e2e.sh`
- **Changes from upstream:**
  - Replaces `$GITHUB_ACTION_PATH` with `e2e` for correct paths
  - Uses temporary file (`$BATS_RUN_TMPDIR/exporter_pids.txt`) to track background exporter process PIDs across tests
  - Implements `setup_file()` to initialize PID tracking file
  - Implements `teardown_file()` to kill tracked processes after all tests complete
  - Includes fallback `pkill` to catch orphaned `jmp run --exporter` processes
  - Uses stderr (`>&2`) for debug output visibility
  - Fixes `JMP_NAME` from `test-exporter-legacy` to `test-client-legacy`
  - Prevents hanging exporter processes after test completion

### `setup-e2e.sh`
- **Destination:** `monorepo/e2e/setup-e2e.sh`
- **Purpose:** One-time setup for e2e testing environment (not in upstream)
- **Usage:** `make e2e-setup` or `bash e2e/setup-e2e.sh`
- **Features:**
  - Installs dependencies (uv, Python, bats)
  - Auto-detects and installs bats helper libraries on macOS
  - Deploys dex with TLS certificates
  - Adds dex.dex.svc.cluster.local to /etc/hosts
  - Installs CA certificate (macOS: login keychain, Linux: system-wide)
  - Configures SSL_CERT_FILE and REQUESTS_CA_BUNDLE for Python
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
  - Trap for INT/TERM signals to cleanup exporters on Ctrl+C

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

1. `fix_kind_cluster_config()` - Updates Kind cluster configuration:
   - `controller/hack/kind_cluster.yaml` - Adds dex nodeport (32000:5556) for e2e tests
2. `setup_github_actions()` - Removes upstream `e2e/action.yml` (e2e workflow uses make targets directly)
3. `copy_e2e_scripts()` - Copies files to the e2e directory:
   - `setup-e2e.sh` - One-time environment setup script
   - `run-e2e.sh` - Test runner script  
   - `tests.bats` - Full replacement of upstream test suite (with cleanup logic)

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
