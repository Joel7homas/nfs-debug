#!/bin/bash
# visibility-testing.sh - Functions for testing NFS/SMB visibility
# Follows minimalist multi-module pattern (max 10 functions per module)

# Source the core utilities if not already loaded
if ! type log_info &> /dev/null; then
    source ./nested-dataset-test-core.sh
fi

# Function: prepare_remote_mount_point
# Description: Prepare NFS mount point on remote host
# Args: $1 - Mount point path
prepare_remote_mount_point() {
    local mount_point="${1:-$TEST_MOUNT_POINT}"
    
    log_info "Preparing remote NFS mount point: ${mount_point}"
    
    # Unmount if already mounted
    ssh_execute_sudo "umount -f ${mount_point} 2>/dev/null || true"
    
    # Create mount point if it doesn't exist
    ssh_execute_sudo "mkdir -p ${mount_point}"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create mount point ${mount_point} on remote host"
        return 1
    fi
    
    log_success "Remote mount point ${mount_point} prepared"
    return 0
}

# Function: prepare_remote_smb_mount_point
# Description: Prepare SMB mount point on remote host
# Args: $1 - Mount point path
prepare_remote_smb_mount_point() {
    local mount_point="${1:-$SMB_MOUNT_POINT}"
    
    log_info "Preparing remote SMB mount point: ${mount_point}"
    
    # Unmount if already mounted
    ssh_execute_sudo "umount -f ${mount_point} 2>/dev/null || true"
    
    # Create mount point if it doesn't exist
    ssh_execute_sudo "mkdir -p ${mount_point}"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create SMB mount point ${mount_point} on remote host"
        return 1
    fi
    
    log_success "Remote SMB mount point ${mount_point} prepared"
    return 0
}

# Function: check_file_visibility
# Description: Check if specific files are visible on remote mount
# Args: $1 - Mount point, $2+ - Files to check
check_file_visibility() {
    local mount_point="$1"
    shift
    local files=("$@")
    
    log_info "Checking file visibility on ${mount_point}"
    
    local visible=0
    local invisible=0
    
    for file in "${files[@]}"; do
        log_info "Checking visibility of ${file}"
        
        # Check if file exists
        ssh_execute "test -f ${mount_point}/${file}"
        
        if [ $? -eq 0 ]; then
            log_success "File ${file} is visible"
            visible=$((visible+1))
        else
            log_warning "File ${file} is NOT visible"
            invisible=$((invisible+1))
        fi
    done
    
    log_info "Visibility summary: ${visible} visible, ${invisible} invisible"
    
    # Return based on visibility
    if [ ${visible} -eq ${#files[@]} ]; then
        return 0  # All files visible
    elif [ ${visible} -gt 0 ]; then
        return 2  # Some files visible
    else
        return 1  # No files visible
    fi
}

# Function: mount_nfs_export
# Description: Mount NFS export on remote host
# Args: $1 - Export path, $2 - Mount point (optional)
mount_nfs_export() {
    local export_path="$1"
    local mount_point="${2:-$TEST_MOUNT_POINT}"
    local server_host=$(hostname -f)
    
    log_info "Mounting NFS export ${export_path} on ${mount_point}"
    
    # Prepare mount point
    prepare_remote_mount_point "${mount_point}"
    
    # Mount
    ssh_execute_sudo "mount -t nfs ${server_host}:${export_path} ${mount_point}"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to mount NFS export ${export_path}"
        return 1
    fi
    
    log_success "NFS export ${export_path} mounted on ${mount_point}"
    return 0
}

# Function: mount_smb_share
# Description: Mount SMB share on remote host
# Args: $1 - Share name, $2 - Mount point (optional)
mount_smb_share() {

    # Ensure CIFS utils are installed
    ssh_execute "command -v mount.cifs > /dev/null || sudo apt-get install -y cifs-utils" || {
        log_warning "Failed to install cifs-utils, but continuing"
    }
    local share_name="$1"
    local mount_point="${2:-$SMB_MOUNT_POINT}"
    local server_host=$(hostname -f)
    
    log_info "Mounting SMB share ${share_name} on ${mount_point}"
    
    # Prepare mount point
    prepare_remote_smb_mount_point "${mount_point}"
    
    # Mount with guest access
    ssh_execute_sudo "mount -t cifs -o guest,vers=3.0,file_mode=0644,dir_mode=0755 //${server_host}/${share_name} ${mount_point}"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to mount SMB share ${share_name}"
        return 1
    fi
    
    log_success "SMB share ${share_name} mounted on ${mount_point}"
    return 0
}

# Function: unmount_remote
# Description: Unmount remote filesystem
# Args: $1 - Mount point
unmount_remote() {
    local mount_point="$1"
    
    log_info "Unmounting ${mount_point} on remote host"
    
    # Unmount
    ssh_execute_sudo "umount -f ${mount_point} 2>/dev/null || true"
    
    # Check if still mounted
    ssh_execute "mount | grep -q ${mount_point}"
    
    if [ $? -eq 0 ]; then
        log_warning "Mount point ${mount_point} is still mounted"
        return 1
    fi
    
    log_success "Mount point ${mount_point} unmounted"
    return 0
}

# Function: test_nfs_visibility
# Description: Test visibility of files via NFS
# Args: $1 - Export path, $2 - Test name, $3+ - Files to check
test_nfs_visibility() {
    local export_path="$1"
    local test_name="$2"
    shift 2
    local files=("$@")
    
    log_header "Testing NFS visibility for ${test_name}"
    
    # Mount export
    mount_nfs_export "${export_path}"
    
    if [ $? -ne 0 ]; then
        record_result "NFS:${test_name}" "MOUNT_FAILED" "Failed to mount NFS export"
        return 1
    fi
    
    # Check file visibility
    check_file_visibility "${TEST_MOUNT_POINT}" "${files[@]}"
    local visibility_result=$?
    
    # Record result
    if [ ${visibility_result} -eq 0 ]; then
        record_result "NFS:${test_name}" "SUCCESS" "All files visible"
    elif [ ${visibility_result} -eq 2 ]; then
        record_result "NFS:${test_name}" "PARTIAL" "Some files visible"
    else
        record_result "NFS:${test_name}" "FAILED" "No files visible"
    fi
    
    # Unmount
    unmount_remote "${TEST_MOUNT_POINT}"
    
    return ${visibility_result}
}

# Function: test_smb_visibility
# Description: Test visibility of files via SMB
# Args: $1 - Share name, $2 - Test name, $3+ - Files to check
test_smb_visibility() {
    local share_name="$1"
    local test_name="$2"
    shift 2
    local files=("$@")
    
    log_header "Testing SMB visibility for ${test_name}"
    
    # Mount share
    mount_smb_share "${share_name}"
    
    if [ $? -ne 0 ]; then
        record_result "SMB:${test_name}" "MOUNT_FAILED" "Failed to mount SMB share"
        return 1
    fi
    
    # Check file visibility
    check_file_visibility "${SMB_MOUNT_POINT}" "${files[@]}"
    local visibility_result=$?
    
    # Record result
    if [ ${visibility_result} -eq 0 ]; then
        record_result "SMB:${test_name}" "SUCCESS" "All files visible"
    elif [ ${visibility_result} -eq 2 ]; then
        record_result "SMB:${test_name}" "PARTIAL" "Some files visible"
    else
        record_result "SMB:${test_name}" "FAILED" "No files visible"
    fi
    
    # Unmount
    unmount_remote "${SMB_MOUNT_POINT}"
    
    return ${visibility_result}
}

# Function: check_directory_structure
# Description: Check directory structure visibility
# Args: $1 - Mount point
check_directory_structure() {
    local mount_point="$1"
    
    log_info "Checking directory structure on ${mount_point}"
    
    # List directory structure
    local dir_listing=$(ssh_execute "find ${mount_point} -type d | sort")
    
    # Print directory structure
    log_info "Directory structure on ${mount_point}:"
    echo "${dir_listing}" | tee -a "${LOG_FILE}"
    
    # Count directories
    local dir_count=$(echo "${dir_listing}" | wc -l)
    log_info "Found ${dir_count} directories"
    
    # Return based on directory count
    if [ ${dir_count} -gt 1 ]; then
        return 0  # Some directories visible
    else
        return 1  # No directories visible
    fi
}
