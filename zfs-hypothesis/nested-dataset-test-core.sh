#!/bin/bash
# nested-dataset-test-core.sh - Core utilities for ZFS nested dataset testing
# Follows minimalist multi-module pattern (max 10 functions per module)

# Configuration - Set default values
REMOTE_HOST=${REMOTE_HOST:-"pita"}
REMOTE_USER=${REMOTE_USER:-"joel"}
BASE_DATASET=${BASE_DATASET:-"data-tank/docker"}
TEST_PARENT=${TEST_PARENT:-"test-parent"}
TEST_CHILD=${TEST_CHILD:-"test-child"}
RESULT_DIR=${RESULT_DIR:-"./results"}
LOG_FILE=${LOG_FILE:-"$RESULT_DIR/nested-dataset-test.log"}
TEST_MOUNT_POINT=${TEST_MOUNT_POINT:-"/mnt/nfs-test"}
SMB_MOUNT_POINT=${SMB_MOUNT_POINT:-"/mnt/smb-test"}
TEST_CASES=("jellyfin" "caddy" "vaultwarden")

# Constants for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function: log_info
# Description: Log informational message
log_info() {
    echo -e "${BLUE}[INFO][$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${LOG_FILE}"
}

# Function: log_success
# Description: Log success message
log_success() {
    echo -e "${GREEN}[SUCCESS][$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${LOG_FILE}"
}

# Function: log_warning
# Description: Log warning message
log_warning() {
    echo -e "${YELLOW}[WARNING][$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${LOG_FILE}"
}

# Function: log_error
# Description: Log error message
log_error() {
    echo -e "${RED}[ERROR][$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${LOG_FILE}"
}

# Function: log_header
# Description: Display a section header
log_header() {
    echo -e "\n${GREEN}=== $1 ===${NC}" | tee -a "${LOG_FILE}"
}

# Function: record_result
# Description: Record test result to results file
record_result() {
    local test_name="$1"
    local result="$2"
    local details="$3"
    
    mkdir -p "${RESULT_DIR}"
    
    echo "RESULT:${test_name}:${result}:${details}" >> "${RESULT_DIR}/nested_dataset_results.txt"
    
    case "${result}" in
        SUCCESS)
            log_success "Test ${test_name}: SUCCESS - ${details}"
            ;;
        PARTIAL)
            log_warning "Test ${test_name}: PARTIAL - ${details}"
            ;;
        FAILED)
            log_error "Test ${test_name}: FAILED - ${details}"
            ;;
        *)
            log_info "Test ${test_name}: ${result} - ${details}"
            ;;
    esac
}

# Function: init_test_environment
# Description: Initialize test environment
init_test_environment() {
    log_header "Initializing test environment"
    
    # Create result directory
    mkdir -p "${RESULT_DIR}"
    
    # Initialize log file
    echo "=== Nested Dataset Test Log - $(date) ===" > "${LOG_FILE}"
    echo "" >> "${LOG_FILE}"
    
    # Record test configuration
    log_info "Test configuration:"
    log_info "Remote host: ${REMOTE_HOST}"
    log_info "Remote user: ${REMOTE_USER}" 
    log_info "Base dataset: ${BASE_DATASET}"
    log_info "Test parent: ${TEST_PARENT}"
    log_info "Test child: ${TEST_CHILD}"
    log_info "Test cases: ${TEST_CASES[*]}"
    
    # Initialize results file
    echo "=== Nested Dataset Test Results - $(date) ===" > "${RESULT_DIR}/nested_dataset_results.txt"
    echo "" >> "${RESULT_DIR}/nested_dataset_results.txt"
    
    log_success "Test environment initialized"
    return 0
}

# Function: ssh_execute
# Description: Execute command on remote host
ssh_execute() {
    local command="$1"
    
    log_info "Executing on ${REMOTE_HOST}: $command" >&2
    ssh "${REMOTE_USER}@${REMOTE_HOST}" "$command"
    return $?
}

# Function: ssh_execute_sudo
# Description: Execute command with sudo on remote host
ssh_execute_sudo() {
    local command="$1"
    
    log_info "Executing with sudo on ${REMOTE_HOST}: $command" >&2
    ssh "${REMOTE_USER}@${REMOTE_HOST}" "sudo $command"
    return $?
}
