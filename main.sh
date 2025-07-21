#!/bin/bash

# Bitbucket Repository Backup Script

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Global variables
SCRIPT_NAME=$(basename "$0")
CONFIG_FILE="config.env"
DRY_RUN=false
VERBOSE=false
SKIP_EXISTING=false
MAX_PARALLEL_JOBS=4
FAILED_REPOS=()
SUCCESSFUL_REPOS=()
TOTAL_REPOS=0
PROCESSED_REPOS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "ERROR") echo -e "[$timestamp] ${RED}[ERROR]${NC} $message" >&2 ;;
        "WARN")  echo -e "[$timestamp] ${YELLOW}[WARN]${NC} $message" >&2 ;;
        "INFO")  echo -e "[$timestamp] ${BLUE}[INFO]${NC} $message" ;;
        "SUCCESS") echo -e "[$timestamp] ${GREEN}[SUCCESS]${NC} $message" ;;
        *)       echo -e "[$timestamp] [$level] $message" ;;
    esac
}

# Usage function
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

A comprehensive Bitbucket repository backup script with automatic discovery,
parallel processing, and error recovery.

OPTIONS:
    -h, --help              Show this help message
    -c, --config FILE       Specify configuration file (default: config.env)
    -d, --dry-run          Show what would be done without executing
    -v, --verbose          Enable verbose output
    -s, --skip-existing    Skip repositories that already exist
    -j, --jobs N           Number of parallel jobs (default: 4)
    --verify               Verify backups after completion

EXAMPLES:
    $SCRIPT_NAME                    # Run with default settings
    $SCRIPT_NAME --dry-run          # See what would be backed up
    $SCRIPT_NAME --verbose --jobs 8 # Verbose output with 8 parallel jobs
    $SCRIPT_NAME --config my.env    # Use custom config file

CONFIGURATION:
    Create config.env from config.env.example and set:
    - ATLASSIAN_EMAIL: Your Atlassian account email
    - API_TOKEN: Your Bitbucket API token
    - ORGNAME: Your Bitbucket workspace name
    - BACKUP_DIR: Directory to store backups

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -s|--skip-existing)
                SKIP_EXISTING=true
                shift
                ;;
            -j|--jobs)
                MAX_PARALLEL_JOBS="$2"
                shift 2
                ;;
            --verify)
                VERIFY_BACKUPS=true
                shift
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Retry function for network operations
retry_command() {
    local max_attempts=3
    local attempt=1
    local delay=5
    
    while [ $attempt -le $max_attempts ]; do
        if "$@"; then
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log "WARN" "Attempt $attempt failed, retrying in ${delay}s..."
            sleep $delay
            ((delay *= 2))  # Exponential backoff
        fi
        ((attempt++))
    done
    
    log "ERROR" "Command failed after $max_attempts attempts: $*"
    return 1
}

# Progress bar function
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))
    
    printf "\r["
    printf "%${filled}s" | tr ' ' '#'
    printf "%${empty}s" | tr ' ' '-'
    printf "] %d%% (%d/%d)" $percentage $current $total
}

# Load and validate configuration
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log "ERROR" "Configuration file not found: $CONFIG_FILE"
        echo "Please copy config.env.example to $CONFIG_FILE and update with your values."
        exit 1
    fi
    
    # Source the configuration file
    source "$CONFIG_FILE"
    
    # Validate required configuration
    if [ -z "${ATLASSIAN_EMAIL:-}" ] || [ -z "${API_TOKEN:-}" ] || [ -z "${ORGNAME:-}" ]; then
        log "ERROR" "Missing required configuration in $CONFIG_FILE"
        echo "Please ensure ATLASSIAN_EMAIL, API_TOKEN, and ORGNAME are set."
        exit 1
    fi
    
    # Set default backup directory if not specified
    BACKUP_DIR="${BACKUP_DIR:-/tmp/bitbucket-backup}"
    
    # Validate configuration
    validate_config
}

# Validate configuration
validate_config() {
    # Check if backup directory is writable
    if [ ! -w "$(dirname "$BACKUP_DIR")" ]; then
        log "ERROR" "Backup directory is not writable: $BACKUP_DIR"
        exit 1
    fi
    
    # Validate API token format (basic check)
    if [[ ! "$API_TOKEN" =~ ^ATATT[0-9A-Za-z_-]+$ ]]; then
        log "WARN" "API token format may be invalid"
    fi
    
    # Validate email format (basic check)
    if [[ ! "$ATLASSIAN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        log "WARN" "Email format may be invalid: $ATLASSIAN_EMAIL"
    fi
    
    log "INFO" "Configuration validated successfully"
}

# Function to get all repositories from Bitbucket workspace
get_repositories() {
    log "INFO" "Fetching repository list from Bitbucket workspace: $ORGNAME" >&2
    
    local temp_file=$(mktemp)
    local http_code
    
    # Use retry logic for API call
    if ! http_code=$(retry_command curl -s -w "%{http_code}" -o "$temp_file" \
        -u "$ATLASSIAN_EMAIL:$API_TOKEN" \
        -H "Accept: application/json" \
        "https://api.bitbucket.org/2.0/repositories/$ORGNAME?pagelen=100"); then
        rm -f "$temp_file"
        exit 1
    fi
    
    # Extract the HTTP status code
    local status_code="${http_code##*$'\n'}"
    
    if [ "$status_code" != "200" ]; then
        log "ERROR" "Failed to fetch repositories from Bitbucket API (HTTP $status_code)" >&2
        rm -f "$temp_file"
        exit 1
    fi
    
    log "SUCCESS" "Successfully connected to Bitbucket API (HTTP $status_code)" >&2
    
    # Extract repository names using jq if available, otherwise use grep
    local repos
    if command -v jq &> /dev/null; then
        repos=$(jq -r '.values[].slug' "$temp_file")
    else
        # Fallback: use grep to extract repository names
        repos=$(grep -o '"slug":"[^"]*"' "$temp_file" | sed 's/"slug":"//g' | sed 's/"//g')
    fi
    
    rm -f "$temp_file"
    echo "$repos"
}

# Process a single repository
process_repository() {
    local repo_name=$1
    local repo_url="https://cyphertek-admin:$API_TOKEN@bitbucket.org/$ORGNAME/$repo_name.git"
    local repo_backup_dir="$BACKUP_DIR/$repo_name"
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would process repository: $repo_name"
        return 0
    fi
    
    # Create backup directory if it doesn't exist
    if [ ! -d "$repo_backup_dir" ]; then
        mkdir -p "$repo_backup_dir"
    fi
    
    # Skip if repository exists and skip-existing is enabled
    if [ "$SKIP_EXISTING" = true ] && [ -d "$repo_backup_dir/.git" ]; then
        log "INFO" "Skipping existing repository: $repo_name"
        return 0
    fi
    
    # Clone or update repository
    if [ ! -d "$repo_backup_dir/.git" ]; then
        log "INFO" "Cloning repository: $repo_name"
        if ! retry_command git clone "$repo_url" "$repo_backup_dir"; then
            log "ERROR" "Failed to clone $repo_name"
            FAILED_REPOS+=("$repo_name")
            return 1
        fi
        log "SUCCESS" "Successfully cloned $repo_name"
    else
        log "INFO" "Repository already exists, updating: $repo_name"
    fi
    
    # Change to repository directory
    cd "$repo_backup_dir"
    
    # Fetch all remote branches
    if ! retry_command git fetch --all; then
        log "ERROR" "Failed to fetch branches for $repo_name"
        FAILED_REPOS+=("$repo_name")
        return 1
    fi
    
    # Get list of all remote branches
    local remote_branches
    remote_branches=$(git branch -r | grep -v HEAD | sed 's/origin\///')
    
    # Update all branches
    local branch_count=0
    local updated_branches=0
    
    for branch in $remote_branches; do
        ((branch_count++))
        if [ "$VERBOSE" = true ]; then
            log "INFO" "  Updating branch: $branch"
        fi
        
        if git checkout "$branch" 2>/dev/null || git checkout -b "$branch" "origin/$branch"; then
            if retry_command git pull origin "$branch"; then
                ((updated_branches++))
                if [ "$VERBOSE" = true ]; then
                    log "SUCCESS" "    Updated $branch branch"
                fi
            else
                log "WARN" "    Failed to update $branch branch"
            fi
        else
            log "WARN" "    Failed to checkout $branch branch"
        fi
    done
    
    log "SUCCESS" "Completed backup of $repo_name ($updated_branches/$branch_count branches updated)"
    SUCCESSFUL_REPOS+=("$repo_name")
    return 0
}

# Verify backup function
verify_backup() {
    local repo_name=$1
    local backup_dir="$BACKUP_DIR/$repo_name"
    
    if [ ! -d "$backup_dir/.git" ]; then
        log "ERROR" "Backup verification failed for $repo_name: No .git directory"
        return 1
    fi
    
    # Check if we can access the repository
    if ! git -C "$backup_dir" log --oneline -1 >/dev/null 2>&1; then
        log "ERROR" "Backup verification failed for $repo_name: Cannot access git log"
        return 1
    fi
    
    # Check if repository has any commits
    local commit_count
    commit_count=$(git -C "$backup_dir" rev-list --count HEAD 2>/dev/null || echo "0")
    if [ "$commit_count" -eq 0 ]; then
        log "WARN" "Backup verification warning for $repo_name: No commits found"
    fi
    
    log "SUCCESS" "Backup verified for $repo_name"
    return 0
}

# Generate summary report
generate_summary() {
    local total_repos=${#REPOSITORIES[@]}
    local successful=${#SUCCESSFUL_REPOS[@]}
    local failed=${#FAILED_REPOS[@]}
    local backup_size
    
    # Calculate backup size
    if [ -d "$BACKUP_DIR" ]; then
        backup_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
    else
        backup_size="N/A"
    fi
    
    echo ""
    echo "=========================================="
    echo "           BACKUP SUMMARY"
    echo "=========================================="
    echo "Total repositories: $total_repos"
    echo "Successful backups: $successful"
    echo "Failed backups: $failed"
    echo "Backup location: $BACKUP_DIR"
    echo "Backup size: $backup_size"
    echo "Backup time: $(date)"
    echo "=========================================="
    
    if [ ${#FAILED_REPOS[@]} -gt 0 ]; then
        echo ""
        echo "Failed repositories:"
        printf '  - %s\n' "${FAILED_REPOS[@]}"
    fi
    
    if [ ${#SUCCESSFUL_REPOS[@]} -gt 0 ]; then
        echo ""
        echo "Successful repositories:"
        printf '  - %s\n' "${SUCCESSFUL_REPOS[@]}"
    fi
}

# Cleanup function
cleanup() {
    log "INFO" "Cleaning up temporary files..."
    rm -f /tmp/bitbucket_backup_*
    
    if [ ${#FAILED_REPOS[@]} -gt 0 ]; then
        log "WARN" "Some repositories failed to backup"
    fi
}

# Main execution
main() {
    # Set trap for cleanup
    trap cleanup EXIT
    
    # Parse arguments
    parse_arguments "$@"
    
    # Load configuration
    load_config
    
    # Show dry run message
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN MODE - No actual changes will be made"
    fi
    
    # Get list of repositories
    local repos_output
    repos_output=$(get_repositories)
    REPOSITORIES=($repos_output)
    TOTAL_REPOS=${#REPOSITORIES[@]}
    
    if [ $TOTAL_REPOS -eq 0 ]; then
        log "ERROR" "No repositories found"
        exit 1
    fi
    
    log "INFO" "Found $TOTAL_REPOS repositories to backup"
    
    if [ "$VERBOSE" = true ]; then
        printf '%s\n' "${REPOSITORIES[@]}"
        echo ""
    fi
    
    # Create backup directory if it doesn't exist
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        log "INFO" "Created backup directory: $BACKUP_DIR"
    fi
    
    # Process repositories
    local current=0
    
    for repo_name in "${REPOSITORIES[@]}"; do
        ((current++))
        
        if [ "$DRY_RUN" = false ]; then
            show_progress $current $TOTAL_REPOS
        fi
        
        # Process repository (with parallel job control if enabled)
        if [ "$MAX_PARALLEL_JOBS" -gt 1 ] && [ "$DRY_RUN" = false ]; then
            # Wait if we have too many jobs running
            while [ $(jobs -r | wc -l) -ge $MAX_PARALLEL_JOBS ]; do
                sleep 0.1  # Small delay instead of wait -n
            done
            
            # Start background job
            process_repository "$repo_name" &
        else
            # Sequential processing
            process_repository "$repo_name"
        fi
        
        ((PROCESSED_REPOS++))
    done
    
    # Wait for all background jobs to complete
    if [ "$MAX_PARALLEL_JOBS" -gt 1 ] && [ "$DRY_RUN" = false ]; then
        wait
    fi
    
    # Clear progress bar
    if [ "$DRY_RUN" = false ]; then
        echo ""
    fi
    
    # Verify backups if requested
    if [ "${VERIFY_BACKUPS:-false}" = true ] && [ "$DRY_RUN" = false ]; then
        log "INFO" "Verifying backups..."
        for repo_name in "${SUCCESSFUL_REPOS[@]}"; do
            verify_backup "$repo_name"
        done
    fi
    
    # Generate summary
    generate_summary
    
    # Exit with error code if any repositories failed
    if [ ${#FAILED_REPOS[@]} -gt 0 ]; then
        exit 1
    fi
}

# Run main function with all arguments
main "$@"