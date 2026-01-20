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

    log_info "GitHub Actions setup complete."
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

    # Setup GitHub Actions
    setup_github_actions
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
