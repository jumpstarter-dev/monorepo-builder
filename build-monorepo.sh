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
    log_info "Copying Makefile to monorepo..."
    cp "${SCRIPT_DIR}/Makefile" "${MONOREPO_DIR}/Makefile"
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
        perl -i -pe 's|^declare -a BRANCHES=\(.*\)$|declare -a BRANCHES=("main")|' "$SCRIPT"
        
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

# Setup GitHub Actions for monorepo
setup_github_actions() {
    log_info "Setting up GitHub Actions..."

    # Copy unified workflows from templates
    mkdir -p "${MONOREPO_DIR}/.github/workflows"
    cp -r "${SCRIPT_DIR}/github_actions/workflows/"* "${MONOREPO_DIR}/.github/workflows/"
    cp "${SCRIPT_DIR}/github_actions/dependabot.yml" "${MONOREPO_DIR}/.github/"

    # Replace e2e/action.yml with monorepo version
    if [ -f "${SCRIPT_DIR}/patches/e2e-action.yml" ]; then
        log_info "Replacing e2e/action.yml with monorepo version..."
        cp "${SCRIPT_DIR}/patches/e2e-action.yml" "${MONOREPO_DIR}/e2e/action.yml"
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
- Adapt e2e/action.yml for monorepo structure (remove separate checkouts)
- Add combined dependabot.yml for all package ecosystems
- Remove old .github directories from controller/, e2e/, protocol/, python/

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

    # Setup GitHub Actions
    setup_github_actions
    echo ""

    # Finalize monorepo (commit changes, add remote)
    finalize_monorepo
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
