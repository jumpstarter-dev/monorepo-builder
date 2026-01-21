#!/bin/bash
#
# build-monorepo.sh
#
# Merges multiple Jumpstarter git repositories into a single monorepo
# while preserving full commit history and authorship.
#
# Usage: ./build-monorepo.sh
#

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="${SCRIPT_DIR}/temp"
MONOREPO_DIR="${SCRIPT_DIR}/monorepo"

# Repository mappings: "url target_subdir"
declare -a REPOS=(
    "https://github.com/jumpstarter-dev/jumpstarter.git python"
    "https://github.com/jumpstarter-dev/jumpstarter-protocol.git protocol"
    "https://github.com/jumpstarter-dev/jumpstarter-controller.git controller"
    "https://github.com/jumpstarter-dev/jumpstarter-e2e.git e2e"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Cleanup function for trap
cleanup() {
    if [ $? -ne 0 ]; then
        log_warn "Script failed. Cleaning up..."
        rm -rf "${TEMP_DIR}"
    fi
}

trap cleanup EXIT

# Check for required dependencies
check_dependencies() {
    log_info "Checking dependencies..."

    if ! command -v git &> /dev/null; then
        log_error "git is not installed. Please install git first."
        exit 1
    fi

    if ! command -v git-filter-repo &> /dev/null; then
        log_error "git-filter-repo is not installed."
        echo "Install it with: pip install git-filter-repo"
        echo "Or via your package manager (e.g., brew install git-filter-repo)"
        exit 1
    fi

    log_info "All dependencies found."
}

# Clone a repository
clone_repo() {
    local url=$1
    local name=$2

    log_info "Cloning ${url}..."
    git clone --single-branch --branch main "${url}" "${TEMP_DIR}/${name}" 2>/dev/null || \
    git clone --single-branch --branch master "${url}" "${TEMP_DIR}/${name}"
}

# Rewrite repository history to subdirectory
rewrite_to_subdir() {
    local name=$1
    local subdir=$2

    log_info "Rewriting ${name} history to ${subdir}/..."
    cd "${TEMP_DIR}/${name}"
    git filter-repo --to-subdirectory-filter "${subdir}" --force
    cd "${SCRIPT_DIR}"
}

# Initialize the monorepo
init_monorepo() {
    log_info "Initializing monorepo..."

    if [ -d "${MONOREPO_DIR}" ]; then
        log_warn "Monorepo directory already exists. Removing it..."
        rm -rf "${MONOREPO_DIR}"
    fi

    mkdir -p "${MONOREPO_DIR}"
    cd "${MONOREPO_DIR}"
    git init
    
    # Create an initial empty commit to have a base
    git commit --allow-empty -m "Initial commit: monorepo creation"
    cd "${SCRIPT_DIR}"
}

# Merge a rewritten repo into monorepo
merge_repo() {
    local name=$1

    log_info "Merging ${name} into monorepo..."
    cd "${MONOREPO_DIR}"
    git remote add "${name}" "${TEMP_DIR}/${name}"
    git fetch "${name}"
    
    # Get the default branch name (main or master)
    local branch
    branch=$(git -C "${TEMP_DIR}/${name}" rev-parse --abbrev-ref HEAD)
    
    git merge "${name}/${branch}" --allow-unrelated-histories --no-edit \
        -m "Merge ${name} repository"
    git remote remove "${name}"
    cd "${SCRIPT_DIR}"
}

# Copy Makefile to monorepo
copy_makefile() {
    log_info "Copying Makefile.monorepo to monorepo..."
    cp "${SCRIPT_DIR}/Makefile.monorepo" "${MONOREPO_DIR}/Makefile"
}

# Copy README to monorepo
copy_readme() {
    log_info "Copying README.md to monorepo..."
    cp "${SCRIPT_DIR}/README.monorepo.md" "${MONOREPO_DIR}/README.md"
}

# Copy typos configuration to monorepo
copy_typos_config() {
    log_info "Copying typos.toml to monorepo..."
    cp "${SCRIPT_DIR}/typos.toml" "${MONOREPO_DIR}/typos.toml"
}

# Fix Python package paths for monorepo structure
fix_python_package_paths() {
    log_info "Fixing Python package paths for monorepo structure..."
    
    # Update raw-options root path in all pyproject.toml files
    # Change from '../../' to '../../../' since python/ is now under monorepo/
    find "${MONOREPO_DIR}/python/packages" -name "pyproject.toml" | while read -r file; do
        # Use perl for portability (works on both macOS and Linux)
        # Replace '../..' with '../../..' in raw-options paths
        perl -i -pe 's|\.\./\.\.|\.\./\.\./\.\.|g' "$file"
    done
    
    # Also fix the template file
    if [ -f "${MONOREPO_DIR}/python/__templates__/driver/pyproject.toml.tmpl" ]; then
        perl -i -pe 's|\.\./\.\.|\.\./\.\./\.\.|g' \
            "${MONOREPO_DIR}/python/__templates__/driver/pyproject.toml.tmpl"
    fi
    
    log_info "Python package paths updated."
}

# Fix multiversion docs script for monorepo structure
fix_multiversion_script() {
    log_info "Fixing multiversion.sh for monorepo structure..."
    
    local SCRIPT="${MONOREPO_DIR}/python/docs/multiversion.sh"
    if [ -f "$SCRIPT" ]; then
        # Update paths to include python/ prefix since worktree is at monorepo root
        # ${WORKTREE} -> ${WORKTREE}/python for project path
        # ${WORKTREE}/docs -> ${WORKTREE}/python/docs for docs path
        perl -i -pe 's|--project "\$\{WORKTREE\}"|--project "\${WORKTREE}/python"|g' "$SCRIPT"
        perl -i -pe 's|"\$\{WORKTREE\}/docs"|"\${WORKTREE}/python/docs"|g' "$SCRIPT"
        perl -i -pe 's|\$\{WORKTREE\}/docs/build|\${WORKTREE}/python/docs/build|g' "$SCRIPT"
        
        # Update BRANCHES array to only contain "main" (but keep array structure for easy additions)
        # COMMENTED OUT: We're merging release branches from python repo to support multi-version docs
        # perl -i -pe 's|^declare -a BRANCHES=\(.*\)$|declare -a BRANCHES=("main")|' "$SCRIPT"
        
        log_info "multiversion.sh updated."
    fi
}

# Fix Python container files for monorepo structure
fix_python_containerfiles() {
    log_info "Fixing Python container files for monorepo structure..."
    
    # Fix Dockerfile
    local DOCKERFILE="${MONOREPO_DIR}/python/Dockerfile"
    if [ -f "$DOCKERFILE" ]; then
        # Remove ARG/ENV lines for GIT_VERSION (no longer needed with real .git)
        perl -i -ne 'print unless /^ARG GIT_VERSION$/' "$DOCKERFILE"
        perl -i -ne 'print unless /^ENV SETUPTOOLS_SCM_PRETEND_VERSION=\$GIT_VERSION$/' "$DOCKERFILE"
        # Update build paths for monorepo structure
        perl -i -pe 's|make -C /src build|make -C /src/python build|g' "$DOCKERFILE"
        perl -i -pe 's|source=/src/dist|source=/src/python/dist|g' "$DOCKERFILE"
        log_info "Dockerfile updated."
    fi
    
    # Fix Containerfile.client
    local CONTAINERFILE="${MONOREPO_DIR}/python/.devfile/Containerfile.client"
    if [ -f "$CONTAINERFILE" ]; then
        # Remove ARG/ENV lines for GIT_VERSION (no longer needed with real .git)
        perl -i -ne 'print unless /^ARG GIT_VERSION$/' "$CONTAINERFILE"
        perl -i -ne 'print unless /^ENV SETUPTOOLS_SCM_PRETEND_VERSION=\$GIT_VERSION$/' "$CONTAINERFILE"
        # Update build paths for monorepo structure
        perl -i -pe 's|make -C /src build|make -C /src/python build|g' "$CONTAINERFILE"
        perl -i -pe 's|source=/src/dist|source=/src/python/dist|g' "$CONTAINERFILE"
        log_info "Containerfile.client updated."
    fi
    
    log_info "Python container files updated for monorepo structure."
}

# Fix e2e dex configuration to use nip.io instead of /etc/hosts
fix_e2e_dex_config() {
    log_info "Fixing e2e dex configuration to use nip.io..."
    
    # Fix dex-csr.json to include dex.127.0.0.1.nip.io in certificate hosts
    local DEX_CSR="${MONOREPO_DIR}/e2e/dex-csr.json"
    if [ -f "$DEX_CSR" ]; then
        perl -i -pe 's|("hosts": \[\s*"dex\.dex\.svc\.cluster\.local")|$1,\n        "dex.127.0.0.1.nip.io"|' "$DEX_CSR"
        log_info "✓ dex-csr.json updated to include dex.127.0.0.1.nip.io"
    fi
    
    # Fix dex.values.yaml to use dex.127.0.0.1.nip.io as issuer
    local DEX_VALUES="${MONOREPO_DIR}/e2e/dex.values.yaml"
    if [ -f "$DEX_VALUES" ]; then
        perl -i -pe 's|https://dex\.dex\.svc\.cluster\.local:5556|https://dex.127.0.0.1.nip.io:5556|g' "$DEX_VALUES"
        log_info "✓ dex.values.yaml updated to use dex.127.0.0.1.nip.io"
    fi
    
    # Fix values.kind.yaml to use dex.127.0.0.1.nip.io as issuer URL
    local VALUES_KIND="${MONOREPO_DIR}/e2e/values.kind.yaml"
    if [ -f "$VALUES_KIND" ]; then
        perl -i -pe 's|url: https://dex\.dex\.svc\.cluster\.local:5556|url: https://dex.127.0.0.1.nip.io:5556|g' "$VALUES_KIND"
        log_info "✓ values.kind.yaml updated to use dex.127.0.0.1.nip.io"
    fi
    
    # Fix tests.bats to use dex.127.0.0.1.nip.io for all login commands
    local TESTS_BATS="${MONOREPO_DIR}/e2e/tests.bats"
    if [ -f "$TESTS_BATS" ]; then
        perl -i -pe 's|https://dex\.dex\.svc\.cluster\.local:5556|https://dex.127.0.0.1.nip.io:5556|g' "$TESTS_BATS"
        # Replace $GITHUB_ACTION_PATH with e2e directory (tests run from monorepo root)
        perl -i -pe 's|\$GITHUB_ACTION_PATH|e2e|g' "$TESTS_BATS"
        log_info "✓ tests.bats updated to use dex.127.0.0.1.nip.io and e2e paths"
    fi
    
    log_info "E2E dex configuration updated (no /etc/hosts modification needed)."
}

# Setup GitHub Actions for monorepo
setup_github_actions() {
    log_info "Setting up GitHub Actions..."

    # Copy unified workflows from templates
    mkdir -p "${MONOREPO_DIR}/.github/workflows"
    cp -r "${SCRIPT_DIR}/github_actions/workflows/"* "${MONOREPO_DIR}/.github/workflows/"
    cp "${SCRIPT_DIR}/github_actions/dependabot.yml" "${MONOREPO_DIR}/.github/"

    # Remove e2e/action.yml (no longer needed, e2e workflow uses make targets directly)
    if [ -f "${MONOREPO_DIR}/e2e/action.yml" ]; then
        log_info "Removing e2e/action.yml (no longer needed)..."
        rm -f "${MONOREPO_DIR}/e2e/action.yml"
    fi

    # Remove old .github directories from merged repos
    for subdir in controller e2e protocol python; do
        if [ -d "${MONOREPO_DIR}/${subdir}/.github" ]; then
            log_info "Removing old .github from ${subdir}/"
            rm -rf "${MONOREPO_DIR}/${subdir}/.github"
        fi
    done

    # Remove component-level typos.toml (using unified root config)
    if [ -f "${MONOREPO_DIR}/controller/typos.toml" ]; then
        log_info "Removing controller/typos.toml (using root config)..."
        rm -f "${MONOREPO_DIR}/controller/typos.toml"
    fi

    log_info "GitHub Actions setup complete."
}

# Copy e2e test scripts
copy_e2e_scripts() {
    log_info "Copying e2e test scripts..."
    
    # Copy setup script
    if [ -f "${SCRIPT_DIR}/patches/setup-e2e.sh" ]; then
        cp "${SCRIPT_DIR}/patches/setup-e2e.sh" "${MONOREPO_DIR}/e2e/setup-e2e.sh"
        chmod +x "${MONOREPO_DIR}/e2e/setup-e2e.sh"
        log_info "✓ E2E setup script installed at e2e/setup-e2e.sh"
    else
        log_warn "Warning: patches/setup-e2e.sh not found, skipping..."
    fi
    
    # Copy run script
    if [ -f "${SCRIPT_DIR}/patches/run-e2e.sh" ]; then
        cp "${SCRIPT_DIR}/patches/run-e2e.sh" "${MONOREPO_DIR}/e2e/run-e2e.sh"
        chmod +x "${MONOREPO_DIR}/e2e/run-e2e.sh"
        log_info "✓ E2E test runner script installed at e2e/run-e2e.sh"
    else
        log_warn "Warning: patches/run-e2e.sh not found, skipping..."
    fi
}

# Commit the GitHub Actions changes and add remote
finalize_monorepo() {
    log_info "Finalizing monorepo..."
    cd "${MONOREPO_DIR}"

    # Stage all changes (deleted old .github dirs, new .github, modified e2e/action.yml)
    git add -A

    # Commit the changes
    git commit -m "$(cat <<'EOF'
Configure monorepo structure

GitHub Actions:
- Move all workflows to unified .github/workflows/ directory
- Add path filters to run workflows only on relevant changes
- Merge duplicate backport workflows into single workflow
- Consolidate lint workflows (Go, Helm, protobuf, Python, typos)
- Merge container image builds (controller + python) into single workflow
- E2E workflow uses make targets (e2e-setup, e2e-run) instead of composite action
- Add combined dependabot.yml for all package ecosystems
- Remove old .github directories from controller/, e2e/, protocol/, python/

Testing:
- Add e2e/setup-e2e.sh script for one-time e2e environment setup
- Add e2e/run-e2e.sh script for running end-to-end tests
- Auto-detects and installs bats helper libraries on macOS
- Update Makefile with 'make e2e-setup', 'make e2e', 'make e2e-full', and 'make e2e-clean' targets
- Split setup and run for faster test iteration
- Configure dex to use dex.127.0.0.1.nip.io (no /etc/hosts modification needed)
- Add e2e-clean target to remove kind cluster, certificates, and virtual environment

Documentation:
- Add unified README.md with overview of all components

Configuration:
- Add typos.toml to exclude false positives (ANDed, mosquitto, etc.)
- Update Python package paths (raw-options root) for monorepo structure
- Update multiversion.sh paths for monorepo worktree structure
- Update Python Dockerfiles to use repo root context (includes .git for hatch-vcs)
EOF
)"

    # Add remote origin
    git remote add origin git@github.com:jumpstarter-dev/monorepo.git

    cd "${SCRIPT_DIR}"
    log_info "Monorepo finalized with remote origin added."
}

# Merge release branches from python repository
merge_python_release_branches() {
    log_info "Merging Python release branches for documentation..."
    
    local PYTHON_URL="https://github.com/jumpstarter-dev/jumpstarter.git"
    local RELEASE_BRANCHES=("release-0.5" "release-0.6" "release-0.7")
    
    for branch in "${RELEASE_BRANCHES[@]}"; do
        log_info "Processing ${branch}..."
        
        # Create a temp directory for this branch
        local BRANCH_DIR="${TEMP_DIR}/python-${branch}"
        
        # Clone the specific branch
        log_info "Cloning ${branch} from python repository..."
        git clone --single-branch --branch "${branch}" "${PYTHON_URL}" "${BRANCH_DIR}"
        
        # Rewrite history to python/ subdirectory
        log_info "Rewriting ${branch} history to python/..."
        cd "${BRANCH_DIR}"
        git filter-repo --to-subdirectory-filter "python" --force
        cd "${SCRIPT_DIR}"
        
        # Merge into monorepo as a branch
        log_info "Merging ${branch} into monorepo..."
        cd "${MONOREPO_DIR}"
        git remote add "python-${branch}" "${BRANCH_DIR}"
        git fetch "python-${branch}"
        
        # Create the branch in monorepo from the fetched branch
        git branch "${branch}" "python-${branch}/${branch}"
        git remote remove "python-${branch}"
        
        # Checkout the branch and apply Python package path fixes
        log_info "Applying Python package path fixes to ${branch}..."
        git checkout "${branch}"
        
        # Apply the same fixes as fix_python_package_paths
        find "${MONOREPO_DIR}/python/packages" -name "pyproject.toml" | while read -r file; do
            perl -i -pe 's|\.\./\.\.|\.\./\.\./\.\.|g' "$file"
        done
        
        if [ -f "${MONOREPO_DIR}/python/__templates__/driver/pyproject.toml.tmpl" ]; then
            perl -i -pe 's|\.\./\.\.|\.\./\.\./\.\.|g' \
                "${MONOREPO_DIR}/python/__templates__/driver/pyproject.toml.tmpl"
        fi
        
        # Commit the fixes if there are changes
        if ! git diff --quiet; then
            git add -A
            git commit -m "Fix Python package paths for monorepo structure"
            log_info "Python package paths fixed and committed for ${branch}."
        fi
        
        # Switch back to main
        git checkout main
        
        cd "${SCRIPT_DIR}"
        log_info "${branch} merged successfully."
        echo ""
    done
    
    log_info "All Python release branches merged."
}

# Main execution
main() {
    log_info "Starting monorepo build process..."
    echo ""

    # Check dependencies
    check_dependencies
    echo ""

    # Clean up any previous temp directory
    if [ -d "${TEMP_DIR}" ]; then
        log_warn "Removing existing temp directory..."
        rm -rf "${TEMP_DIR}"
    fi
    mkdir -p "${TEMP_DIR}"

    # Clone and rewrite each repository
    for repo_entry in "${REPOS[@]}"; do
        read -r url subdir <<< "${repo_entry}"
        name=$(basename "${url}" .git)
        
        clone_repo "${url}" "${name}"
        rewrite_to_subdir "${name}" "${subdir}"
        echo ""
    done

    # Initialize monorepo
    init_monorepo
    echo ""

    # Merge all repositories
    for repo_entry in "${REPOS[@]}"; do
        read -r url subdir <<< "${repo_entry}"
        name=$(basename "${url}" .git)
        
        merge_repo "${name}"
        echo ""
    done

    # Copy Makefile
    copy_makefile
    echo ""

    # Copy README
    copy_readme
    echo ""

    # Copy typos configuration
    copy_typos_config
    echo ""

    # Fix Python package paths for monorepo structure
    fix_python_package_paths
    echo ""

    # Fix multiversion docs script
    fix_multiversion_script
    echo ""

    # Fix Python container files
    fix_python_containerfiles
    echo ""

    # Fix e2e dex configuration
    fix_e2e_dex_config
    echo ""

    # Setup GitHub Actions
    setup_github_actions
    echo ""

    # Copy e2e test scripts
    copy_e2e_scripts
    echo ""

    # Finalize monorepo (commit changes, add remote)
    finalize_monorepo
    echo ""

    # Merge Python release branches for documentation
    merge_python_release_branches
    echo ""

    # Clean up temp directory
    log_info "Cleaning up temp directory..."
    rm -rf "${TEMP_DIR}"

    log_info "Monorepo created successfully at: ${MONOREPO_DIR}"
    echo ""
    echo "Next steps:"
    echo "  cd ${MONOREPO_DIR}"
    echo "  git log --oneline  # View combined history"
    echo "  make help          # View available make targets"
}

main "$@"
