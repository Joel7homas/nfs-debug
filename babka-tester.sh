#!/bin/bash
# babka-tester.sh - Main controller for NFS testing
# Implements the minimalist multi-module pattern (max 10 functions per module)

# Script directory for relative imports
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration - shared across all modules
export REMOTE_HOST="pita"
export REMOTE_USER="joel"
export EXPORT_PATH="/mnt/data-tank/docker"
export REMOTE_MOUNT_POINT="/mnt/nfs-test"
export REMOTE_NFS_MOUNT="/mnt/nfs-temp"
export REMOTE_BINDFS_MOUNT="/mnt/bindfs-test"
export REMOTE_SMB_MOUNT="/mnt/smb-test"
export SMB_SHARE_NAME="docker"
export TEST_DIRS=("caddy" "actual-budget" "homer" "vaultwarden" "seafile")

# Directory structure
export LIB_DIR="${SCRIPT_DIR}/lib"
export ORIGINAL_DIR="${SCRIPT_DIR}/original"
export PATCHED_DIR="${SCRIPT_DIR}/patched"
export RESULT_DIR="${SCRIPT_DIR}/results"
export BACKUP_DIR="${SCRIPT_DIR}/backups"
export LOG_FILE="${RESULT_DIR}/babka-tester.log"
export TEST_STATUS_FILE="${RESULT_DIR}/test_status.txt"

# Source core utilities
source "${LIB_DIR}/utils-core.sh"

# Function: show_banner
# Description: Display a welcome banner
show_banner() {
    echo "==============================================="
    echo "  BABKA-PITA NFS TROUBLESHOOTING FRAMEWORK"
    echo "  Minimalist Multi-Module Implementation"
    echo "==============================================="
    echo "  Server: babka (TrueNAS Scale)"
    echo "  Client: pita (Ubuntu)"
    echo "  Export: ${EXPORT_PATH}"
    echo "==============================================="
    echo ""
}

# Function: initialize_environment
# Description: Set up directories and check dependencies
initialize_environment() {
    log_header "Initializing test environment"
    
    # Create necessary directories
    mkdir -p "${RESULT_DIR}" "${BACKUP_DIR}" "${PATCHED_DIR}"
    
    # Initialize status file
    update_status "INITIALIZING"
    
    # Check dependencies
    check_dependencies
    if [ $? -ne 0 ]; then
        log_error "Missing dependencies. Please install required packages."
        return 1
    fi
    
    # Verify SSH connectivity
    source "${LIB_DIR}/utils-ssh.sh"
    check_ssh_connectivity
    if [ $? -ne 0 ]; then
        log_error "Cannot connect to remote host ${REMOTE_HOST} as ${REMOTE_USER}"
        return 1
    fi
    
    # Check if original scripts directory exists
    if [ ! -d "${ORIGINAL_DIR}" ]; then
        log_error "Original scripts directory not found: ${ORIGINAL_DIR}"
        return 1
    fi
    
    # Check if lib directory exists
    if [ ! -d "${LIB_DIR}" ]; then
        log_error "Lib directory not found: ${LIB_DIR}"
        return 1
    fi
    
    log_success "Environment initialized successfully"
    update_status "INITIALIZED"
    return 0
}

# Function: apply_patches
# Description: Apply patches to original scripts
apply_patches() {
    log_header "Applying patches to original scripts"
    
    # Source patch scripts one by one
    source "${LIB_DIR}/utils-ssh.sh"
    
    # Apply patches in sequence
    source "${SCRIPT_DIR}/patches/patch-mount.sh"
    if [ $? -ne 0 ]; then
        log_error "Failed to apply mount patches"
        return 1
    fi
    
    source "${SCRIPT_DIR}/patches/patch-content.sh"
    if [ $? -ne 0 ]; then
        log_error "Failed to apply content patches"
        return 1
    fi
    
    log_success "All patches applied successfully"
    update_status "PATCHED"
    return 0
}

# Function: run_server_tests
# Description: Run server-side configuration tests
run_server_tests() {
    log_header "Running server-side configuration tests"
    
    # Source server configuration modules
    source "${LIB_DIR}/server-config-core.sh"
    
    # Backup current configurations
    backup_server_configs
    
    # Run NFS server tests
    source "${LIB_DIR}/server-config-nfs.sh"
    test_all_nfs_configs
    
    log_success "Server-side tests completed"
    update_status "SERVER_TESTS_COMPLETE"
    return 0
}

# Function: run_client_tests
# Description: Run client-side mount tests
run_client_tests() {
    log_header "Running client-side mount tests"
    
    # Source client mount modules
    source "${LIB_DIR}/client-mount-core.sh"
    
    # Run NFS client tests
    source "${LIB_DIR}/client-mount-nfs.sh"
    test_nfs_client_mounts
    
    log_success "Client-side tests completed"
    update_status "CLIENT_TESTS_COMPLETE"
    return 0
}

# Function: run_alternative_tests
# Description: Run alternative approach tests
run_alternative_tests() {
    log_header "Running alternative approach tests"
    
    # Test bindfs approach
    source "${LIB_DIR}/alt-bindfs.sh"
    test_bindfs_solutions
    
    # Test SMB approach
    source "${LIB_DIR}/alt-smb.sh"
    test_smb_solutions
    
    log_success "Alternative tests completed"
    update_status "ALTERNATIVE_TESTS_COMPLETE"
    return 0
}

# Function: generate_report
# Description: Generate final report
generate_report() {
    log_header "Generating final test report"
    
    # Source reporting modules
    source "${LIB_DIR}/report-core.sh"
    
    # Generate the report
    generate_final_report
    
    log_success "Report generation completed"
    update_status "REPORT_COMPLETE"
    return 0
}

# Function: cleanup
# Description: Clean up temporary files and restore original configurations
cleanup() {
    log_header "Cleaning up test environment"
    
    # Source backup utilities
    source "${LIB_DIR}/utils-backup.sh"
    
    # Restore server configurations
    restore_server_configs
    
    # Clean up remote mount points
    source "${LIB_DIR}/utils-ssh.sh"
    ssh_unmount "${REMOTE_MOUNT_POINT}"
    ssh_unmount "${REMOTE_NFS_MOUNT}"
    ssh_unmount "${REMOTE_BINDFS_MOUNT}"
    ssh_unmount "${REMOTE_SMB_MOUNT}"
    
    log_success "Cleanup completed"
    update_status "COMPLETE"
    return 0
}

# Function: main
# Description: Main function orchestrating the entire process
main() {
    show_banner
    
    # Initialize environment
    initialize_environment
    if [ $? -ne 0 ]; then
        log_error "Initialization failed. Exiting."
        exit 1
    fi
    
    # Apply patches to original scripts
    apply_patches
    if [ $? -ne 0 ]; then
        log_error "Patching failed. Exiting."
        exit 1
    fi
    
    # Run server-side tests
    run_server_tests
    
    # Run client-side tests
    run_client_tests
    
    # Run alternative approach tests
    run_alternative_tests
    
    # Generate final report
    generate_report
    
    # Clean up
    cleanup
    
    log_success "All tests completed successfully"
    echo ""
    echo "Report generated: ${RESULT_DIR}/nfs_test_report.md"
    echo ""
    echo "Thank you for using the Babka-Pita NFS Troubleshooting Framework!"
    
    return 0
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
