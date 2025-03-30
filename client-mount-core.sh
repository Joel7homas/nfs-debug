#!/bin/bash
# client-mount-core.sh - Core client mount testing functions
# Implements the minimalist multi-module pattern (max 10 functions per module)

# Ensure we have core utilities
if ! type log_info &> /dev/null; then
    echo "ERROR: utils-core.sh must be sourced before client-mount-core.sh"
    exit 1
fi

# Ensure we have SSH utilities
if ! type ssh_execute &> /dev/null; then
    echo "ERROR: utils-ssh.sh must be sourced before client-mount-core.sh"
    exit 1
fi

# Function: prepare_remote_mount_point
# Description: Ensure mount point exists and is unmounted on remote host
prepare_remote_mount_point() {
    local mount_point="${REMOTE_MOUNT_POINT:-/mnt/nfs-test}"
    
    log_info "Preparing remote mount point: $mount_point"
    
    # Ensure any existing mount is unmounted
    ssh_unmount "$mount_point"
    
    # Create the mount point if it doesn't exist
    ssh_create_dir "$mount_point"
    
    if [ $? -eq 0 ]; then
        log_success "Remote mount point ready: $mount_point"
        return 0
    else
        log_error "Failed to prepare remote mount point: $mount_point"
        return 1
    fi
}

# Function: test_basic_mount
# Description: Test basic mount functionality with default options
# Args: $1 - NFS version (optional, defaults to v3)
test_basic_mount() {
    local nfs_version="${1:-""}"
    local mount_point="${REMOTE_MOUNT_POINT:-/mnt/nfs-test}"
    local server_host=$(hostname -f)
    local export_path="${EXPORT_PATH:-/mnt/data-tank/docker}"
    
    log_info "Testing basic NFS$nfs_version mount"
    
    # Prepare mount point
    prepare_remote_mount_point
    
    # Attempt mount
    ssh_execute_sudo "mount -t nfs$nfs_version $server_host:$export_path $mount_point"
    local mount_result=$?
    
    if [ $mount_result -ne 0 ]; then
        log_error "Basic mount failed"
        return 1
    fi
    
    log_success "Basic mount successful"
    
    # Check content visibility
    ssh_get_content_visibility "$mount_point" "${TEST_DIRS[@]}"
    local content_result=$?
    
    # Unmount
    ssh_unmount "$mount_point"
    
    return $content_result
}

# Function: test_mount_with_options
# Description: Test mount with specific options
# Args: $1 - Mount options, $2 - NFS version (optional), $3 - Description (optional)
test_mount_with_options() {
    local mount_options="$1"
    local nfs_version="${2:-""}"
    local description="${3:-"Custom options"}"
    local mount_point="${REMOTE_MOUNT_POINT:-/mnt/nfs-test}"
    local server_host=$(hostname -f)
    local export_path="${EXPORT_PATH:-/mnt/data-tank/docker}"
    
    log_info "Testing NFS$nfs_version mount with $description: $mount_options"
    
    # Prepare mount point
    prepare_remote_mount_point
    
    # Attempt mount with options
    ssh_execute_sudo "mount -t nfs$nfs_version -o $mount_options $server_host:$export_path $mount_point"
    local mount_result=$?
    
    if [ $mount_result -ne 0 ]; then
        log_error "Mount with options failed: $mount_options"
        echo "RESULT:MOUNT:$description:FAILED" >> "${RESULT_DIR}/mount_results.log"
        return 1
    fi
    
    log_success "Mount with options successful: $mount_options"
    
    # Check content visibility
    ssh_get_content_visibility "$mount_point" "${TEST_DIRS[@]}"
    local content_result=$?
    
    # Record result
    if [ $content_result -eq 0 ]; then
        log_success "Mount successful with content: $description"
        echo "RESULT:MOUNT:$description:SUCCESS" >> "${RESULT_DIR}/mount_results.log"
    elif [ $content_result -eq 2 ]; then
        log_warning "Mount partially successful: $description"
        echo "RESULT:MOUNT:$description:PARTIAL" >> "${RESULT_DIR}/mount_results.log"
    else
        log_error "Mount without content: $description"
        echo "RESULT:MOUNT:$description:NO_CONTENT" >> "${RESULT_DIR}/mount_results.log"
    fi
    
    # Unmount
    ssh_unmount "$mount_point"
    
    return $content_result
}

# Function: verify_mount_permissions
# Description: Check permissions on mounted directories
verify_mount_permissions() {
    local mount_point="${REMOTE_MOUNT_POINT:-/mnt/nfs-test}"
    
    log_info "Verifying mount permissions"
    
    # Check if mounted
    if ! ssh_check_mount "$mount_point"; then
        log_error "Mount point not mounted: $mount_point"
        return 1
    fi
    
    # Get directory permissions
    local permissions=$(ssh_execute "ls -la $mount_point | head -n 20")
    log_info "Directory permissions:\n$permissions"
    
    # Check if test user can read files
    ssh_execute "find $mount_point -type f -name \"*.txt\" -o -name \"*.conf\" | head -n 5 | xargs cat > /dev/null 2>&1"
    local read_result=$?
    
    if [ $read_result -eq 0 ]; then
        log_success "User can read files in the mount"
    else
        log_warning "User may not have read permissions on files"
    fi
    
    # Check if test user can create a test file
    local test_file="$mount_point/nfs-test-$(date +%s).txt"
    ssh_execute "echo 'test' > $test_file"
    local write_result=$?
    
    if [ $write_result -eq 0 ]; then
        log_success "User can write to the mount"
        # Clean up test file
        ssh_execute "rm -f $test_file"
    else
        log_warning "User cannot write to the mount"
    fi
    
    return 0
}

# Function: check_remote_nfs_client_config
# Description: Check NFS client configuration on remote host
check_remote_nfs_client_config() {
    log_info "Checking remote NFS client configuration"
    
    # Check if NFS client is installed
    ssh_execute "command -v mount.nfs"
    if [ $? -ne 0 ]; then
        log_error "NFS client not installed on remote host"
        return 1
    fi
    
    # Check NFS client version
    local nfs_version=$(ssh_execute "mount.nfs -V 2>&1 | head -n 1")
    log_info "Remote NFS client version: $nfs_version"
    
    # Check if rpcbind is running
    ssh_execute "systemctl is-active rpcbind"
    if [ $? -ne 0 ]; then
        log_warning "rpcbind service may not be running on remote host"
    else
        log_success "rpcbind service is running"
    fi
    
    # Check if idmapd is running (for NFSv4)
    ssh_execute "systemctl is-active nfs-idmapd"
    if [ $? -ne 0 ]; then
        log_warning "nfs-idmapd service may not be running on remote host"
    else
        log_success "nfs-idmapd service is running"
    fi
    
    # Check idmapd.conf if it exists
    ssh_execute "[ -f /etc/idmapd.conf ] && grep -v '^#' /etc/idmapd.conf | grep -v '^$'"
    
    return 0
}

# Function: remote_client_info
# Description: Gather system information from the remote client
remote_client_info() {
    log_info "Gathering remote client information"
    
    # Get hostname
    local hostname=$(ssh_execute "hostname")
    log_info "Remote hostname: $hostname"
    
    # Get OS information
    local os_info=$(ssh_execute "cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2")
    log_info "Remote OS: $os_info"
    
    # Get kernel version
    local kernel=$(ssh_execute "uname -r")
    log_info "Remote kernel: $kernel"
    
    # Get mounted filesystems
    log_info "Remote mounted filesystems:"
    ssh_execute "mount | grep -E 'type (nfs|nfs4)'"
    
    # Save complete system information to a file
    ssh_execute "hostname && uname -a && cat /etc/os-release && mount" > "${RESULT_DIR}/remote_system_info.txt"
    
    log_success "Remote client information gathered"
    return 0
}

# Function: test_directory_permissions
# Description: Test permissions on specific directories
test_directory_permissions() {
    local mount_point="${REMOTE_MOUNT_POINT:-/mnt/nfs-test}"
    
    log_info "Testing directory permissions"
    
    # Check if mounted
    if ! ssh_check_mount "$mount_point"; then
        log_error "Mount point not mounted: $mount_point"
        return 1
    fi
    
    # Test each directory
    for dir in "${TEST_DIRS[@]}"; do
        log_info "Testing permissions for directory: $dir"
        
        # Check if directory exists
        ssh_execute "[ -d $mount_point/$dir ]"
        if [ $? -ne 0 ]; then
            log_warning "Directory doesn't exist: $dir"
            continue
        fi
        
        # Get directory permissions
        local dir_perms=$(ssh_execute "ls -la $mount_point/$dir | head -n 2 | tail -n 1")
        log_info "Directory permissions: $dir_perms"
        
        # Try to list directory contents
        local dir_count=$(ssh_execute "find $mount_point/$dir -maxdepth 1 | wc -l")
        log_info "Items in directory: $dir_count"
        
        # Try to access a file if any exist
        ssh_execute "find $mount_point/$dir -type f -print -quit | xargs cat > /dev/null 2>&1"
        if [ $? -eq 0 ]; then
            log_success "Can access files in $dir"
        else
            log_warning "Cannot access files in $dir"
        fi
    done
    
    return 0
}
