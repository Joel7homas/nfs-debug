#!/bin/bash
# utils-core.sh - Core utility functions for NFS testing
# Implements the minimalist multi-module pattern (max 10 functions per module)

# Constants for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function: log_info
# Description: Log informational message
# Args: $1 - Message to log
log_info() {
    echo -e "${BLUE}[INFO][$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${LOG_FILE:-/dev/null}"
}

# Function: log_success
# Description: Log success message
# Args: $1 - Message to log
log_success() {
    echo -e "${GREEN}[SUCCESS][$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${LOG_FILE:-/dev/null}"
}

# Function: log_warning
# Description: Log warning message
# Args: $1 - Message to log
log_warning() {
    echo -e "${YELLOW}[WARNING][$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${LOG_FILE:-/dev/null}"
}

# Function: log_error
# Description: Log error message
# Args: $1 - Message to log
log_error() {
    echo -e "${RED}[ERROR][$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${LOG_FILE:-/dev/null}"
}

# Function: log_header
# Description: Display a section header
# Args: $1 - Header text
log_header() {
    echo -e "\n${GREEN}=== $1 ===${NC}" | tee -a "${LOG_FILE:-/dev/null}"
}

# Function: update_status
# Description: Update the status file with current progress
# Args: $1 - Status message
update_status() {
    local status="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Create status directory if it doesn't exist
    mkdir -p "$(dirname "${TEST_STATUS_FILE:-./results/test_status.txt}")"
    
    # Update status file
    echo "STATUS:$status:$timestamp" > "${TEST_STATUS_FILE:-./results/test_status.txt}"
    log_info "Status updated: $status"
}

# Function: check_dependencies
# Description: Check for required tools and commands
# Returns: 0 if all dependencies are satisfied, 1 otherwise
check_dependencies() {
    log_info "Checking dependencies..."
    local missing=0
    
    # Check for SSH client
    if ! command -v ssh &> /dev/null; then
        log_error "SSH client not found"
        missing=1
    fi
    
    # Check for sed
    if ! command -v sed &> /dev/null; then
        log_error "sed not found"
        missing=1
    fi
    
    # Check for jq (used for JSON manipulation with TrueNAS API)
    if ! command -v jq &> /dev/null; then
        log_error "jq not found"
        missing=1
    fi
    
    if [ $missing -eq 0 ]; then
        log_success "All dependencies satisfied"
        return 0
    else
        log_error "Missing dependencies. Please install them and try again."
        return 1
    fi
}

# Function: check_ssh_connectivity
# Description: Verify SSH connectivity to remote host
# Returns: 0 if connection successful, 1 otherwise
check_ssh_connectivity() {
    if [ -z "${REMOTE_HOST}" ] || [ -z "${REMOTE_USER}" ]; then
        log_error "Remote host or user not defined"
        return 1
    fi
    
    log_info "Checking SSH connectivity to ${REMOTE_USER}@${REMOTE_HOST}..."
    
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "${REMOTE_USER}@${REMOTE_HOST}" "echo 'Connection successful'" &> /dev/null; then
        log_success "SSH connection to ${REMOTE_HOST} successful"
        return 0
    else
        log_error "Failed to connect to ${REMOTE_HOST} via SSH"
        return 1
    fi
}

# Function: clean_exit
# Description: Clean up and exit script
# Args: $1 - Exit code (optional, defaults to 0)
clean_exit() {
    local exit_code=${1:-0}
    
    if [ $exit_code -eq 0 ]; then
        log_success "Execution completed successfully"
        update_status "COMPLETED"
    else
        log_error "Execution failed with exit code $exit_code"
        update_status "FAILED"
    fi
    
    exit $exit_code
}
