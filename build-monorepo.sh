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

# Commit helper function
# Usage: git_commit "Commit title" "Optional detailed message"
git_commit() {
    local title="$1"
    local details="$2"
    
    cd "${MONOREPO_DIR}"
    
    # Check if there are any changes to commit
    if git diff --quiet && git diff --cached --quiet; then
        log_info "No changes to commit for: ${title}"
        cd "${SCRIPT_DIR}"
        return 0
    fi
    
    # Stage all changes
    git add -A
    
    # Create commit message
    local commit_msg="$title"
    if [ -n "$details" ]; then
        commit_msg="$(cat <<EOF
$title

$details
EOF
)"
    fi
    
    # Commit
    git commit -m "$commit_msg"
    log_info "✓ Committed: ${title}"
    
    cd "${SCRIPT_DIR}"
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

# Copy import_pr.sh script to monorepo
copy_import_pr_script() {
    log_info "Copying import_pr.sh to monorepo..."
    cp "${SCRIPT_DIR}/import_pr.sh" "${MONOREPO_DIR}/import_pr.sh"
    chmod +x "${MONOREPO_DIR}/import_pr.sh"
}

# Copy typos configuration to monorepo
copy_typos_config() {
    log_info "Copying typos.toml to monorepo..."
    cp "${SCRIPT_DIR}/typos.toml" "${MONOREPO_DIR}/typos.toml"
}

# Create root .gitignore for monorepo
create_gitignore() {
    log_info "Creating root .gitignore for monorepo..."
    cat > "${MONOREPO_DIR}/.gitignore" <<'EOF'
# E2E test artifacts and local configuration
.e2e-setup-complete
.e2e/
.bats/
ca.pem
ca-key.pem
ca.csr
server.pem
server-key.pem
server.csr

# Python
.venv/
__pycache__/
*.pyc
*.pyo
*.egg-info/
dist/
build/

# Editor/IDE
.vscode/
.idea/
*.swp
*.swo
*~
.DS_Store
EOF
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
        
        # Remove release-0.5 from BRANCHES array
        perl -i -pe 's/"release-0\.5"\s*//g' "$SCRIPT"
        
        log_info "multiversion.sh updated (removed release-0.5)."
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

# Fix e2e values to use placeholder and patch deploy script
fix_e2e_values() {
    log_info "Setting up e2e values configuration..."
    
    # Ensure e2e/values.kind.yaml has placeholder for certificate
    local E2E_VALUES="${MONOREPO_DIR}/e2e/values.kind.yaml"
    if [ -f "$E2E_VALUES" ]; then
        # Replace any existing certificate with placeholder
        perl -i -0777 -pe 's/certificateAuthority:\s*\|[\s\S]*?-----END CERTIFICATE-----/certificateAuthority: placeholder/g' "$E2E_VALUES"
        log_info "✓ E2E values configured with certificate placeholder"
    fi
    
    # Ensure controller values.kind.yaml also has placeholder
    local CONTROLLER_VALUES="${MONOREPO_DIR}/controller/deploy/helm/jumpstarter/values.kind.yaml"
    if [ -f "$CONTROLLER_VALUES" ]; then
        # Replace any existing certificate with placeholder
        perl -i -0777 -pe 's/certificateAuthority:\s*\|[\s\S]*?-----END CERTIFICATE-----/certificateAuthority: placeholder/g' "$CONTROLLER_VALUES"
        log_info "✓ Controller values configured with certificate placeholder"
    fi
    
    # Patch deploy_with_helm.sh to support EXTRA_VALUES environment variable
    local DEPLOY_SCRIPT="${MONOREPO_DIR}/controller/hack/deploy_with_helm.sh"
    if [ -f "$DEPLOY_SCRIPT" ]; then
        # Add EXTRA_VALUES support to helm command (after values.kind.yaml, before jumpstarter)
        perl -i -pe 's|(--values ./deploy/helm/jumpstarter/values\.kind\.yaml)(\s+jumpstarter)|$1 \${EXTRA_VALUES}$2|' "$DEPLOY_SCRIPT"
        log_info "✓ Patched deploy_with_helm.sh to support EXTRA_VALUES"
    fi
}

# Copy Kind cluster config with dex nodeport pre-configured
copy_kind_cluster_config() {
    log_info "Copying Kind cluster config for e2e tests..."
    
    local KIND_CONFIG="${MONOREPO_DIR}/controller/hack/kind_cluster.yaml"
    local PATCHES_KIND_CONFIG="${SCRIPT_DIR}/patches/kind_cluster.yaml"
    
    if [ -f "$PATCHES_KIND_CONFIG" ]; then
        cp "$PATCHES_KIND_CONFIG" "$KIND_CONFIG"
        log_info "✓ Kind cluster config copied (includes dex nodeport)"
    else
        log_warn "Patches kind_cluster.yaml not found, skipping..."
    fi
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
    
    # Copy tests.bats (replaces upstream version)
    if [ -f "${SCRIPT_DIR}/patches/tests.bats" ]; then
        cp "${SCRIPT_DIR}/patches/tests.bats" "${MONOREPO_DIR}/e2e/tests.bats"
        log_info "✓ E2E tests.bats installed at e2e/tests.bats"
    else
        log_warn "Warning: patches/tests.bats not found, skipping..."
    fi
}

# Finalize monorepo and add remote
finalize_monorepo() {
    log_info "Finalizing monorepo..."
    cd "${MONOREPO_DIR}"

    # Commit any remaining uncommitted changes
    if ! git diff --quiet || ! git diff --cached --quiet; then
        git add -A
        git commit -m "Apply remaining monorepo adjustments"
        log_info "✓ Committed remaining changes"
    fi

    # Add remote origin
    git remote add origin git@github.com:jumpstarter-dev/monorepo.git
    log_info "✓ Remote origin added"

    cd "${SCRIPT_DIR}"
    log_info "Monorepo finalized."
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

    # Copy import_pr.sh script
    copy_import_pr_script
    echo ""

    # Copy typos configuration
    copy_typos_config
    echo ""

    # Create root .gitignore
    create_gitignore
    echo ""

    # git commit
    git_commit "Add root configuration files" "- Add Makefile with unified build targets
- Add README.md with monorepo overview
- Add import_pr.sh for importing upstream PRs
- Add typos.toml configuration
- Add .gitignore for monorepo artifacts (.e2e/, .bats/, certificates, etc.)"
    echo ""

    # Fix Python package paths for monorepo structure
    fix_python_package_paths
    echo ""

    # git commit
    git_commit "Fix Python package paths for monorepo structure" "Update pyproject.toml files to adjust raw-options root paths
from '../..' to '../../..' to account for monorepo subdirectory."
    echo ""

    # Fix multiversion docs script
    fix_multiversion_script
    echo ""

    # git commit
    git_commit "Fix multiversion docs script for monorepo" "Update multiversion.sh to use correct paths with python/ prefix
in worktree structure."
    echo ""

    # Fix Python container files
    fix_python_containerfiles
    echo ""

    # Fix e2e values configuration
    fix_e2e_values
    echo ""

    # Copy Kind cluster config
    copy_kind_cluster_config
    echo ""

    # git commit
    git_commit "Fix controller and e2e configurations" "- Update Python container files for monorepo build paths
- Copy Kind cluster config with dex nodeport pre-configured
- Configure controller and e2e values with certificate placeholder
- Patch deploy_with_helm.sh to support EXTRA_VALUES for Helm overlay pattern"
    echo ""

    # Setup GitHub Actions
    setup_github_actions
    echo ""

    # Copy e2e test scripts
    copy_e2e_scripts
    echo ""

    # git commit
    git_commit "Configure GitHub Actions and e2e test scripts" "- Add unified GitHub Actions workflows with path filters
- Configure dependabot for all package ecosystems
- Remove old .github directories from subdirectories
- Install e2e test scripts (setup-e2e.sh, run-e2e.sh, tests.bats)"
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
