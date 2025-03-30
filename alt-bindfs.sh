#!/bin/bash
# alt-bindfs.sh - Functions for testing bindfs solutions
# Implements the minimalist multi-module pattern (max 10 functions per module)

# Ensure we have core utilities
if ! type log_info &> /dev/null; then
    echo "ERROR: utils-core.sh must be sourced before alt-bindfs.sh"
    exit 1
fi

# Ensure we have SSH utilities
if ! type ssh_execute &> /dev/null; then
    echo "ERROR: utils-ssh.sh must be sourced before alt-bindfs.sh"
    exit 1
fi

# Function: check_bindfs_installed
# Description: Check if bindfs is installed on remote host
check_bindfs_installed() {
    log_info "Checking if bindfs is installed on remote host"
    
    ssh_execute "command -v bindfs"
    if [ $? -ne 0 ]; then
        log_warning "bindfs not installed on remote host"
        
        # Try to install bindfs
        log_info "Attempting to install bindfs on remote host"
        ssh_execute_sudo "apt-get update && apt-get install -y bindfs"
        
        # Check if installation was successful
        ssh_execute "command -v bindfs"
        if [ $? -ne 0 ]; then
            log_error "Failed to install bindfs on remote host"
            return 1
        fi
        
        log_success "bindfs installed on remote host"
    else
        log_success "bindfs already installed on remote host"
    fi
    
    return 0
}

# Function: prepare_bindfs_mounts
# Description: Prepare mount points for bindfs testing
prepare_bindfs_mounts() {
    local nfs_mount="${REMOTE_NFS_MOUNT:-/mnt/nfs-temp}"
    local bindfs_mount="${REMOTE_BINDFS_MOUNT:-/mnt/bindfs-test}"
    
    log_info "Preparing mount points for bindfs testing"
    
    # Unmount any existing mounts
    ssh_unmount "$bindfs_mount"
    ssh_unmount "$nfs_mount"
    
    # Create mount points
    ssh_create_dir "$nfs_mount"
    ssh_create_dir "$bindfs_mount"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create bind mount points"
        return 1
    fi
    
    log_success "Bindfs mount points prepared"
    return 0
}

# Function: test_bindfs_solution
# Description: Test a specific bindfs configuration
# Args: $1 - Description, $2 - NFS options, $3 - bindfs options, $4 - NFS version (optional)
test_bindfs_solution() {
    local description="$1"
    local nfs_options="$2"
    local bindfs_options="$3"
    local nfs_version="${4:-""}"
    local nfs_mount="${REMOTE_NFS_MOUNT:-/mnt/nfs-temp}"
    local bindfs_mount="${REMOTE_BINDFS_MOUNT:-/mnt/bindfs-test}"
    
    log_header "Testing bindfs solution: $description"
    
    # Check if bindfs is installed
    check_bindfs_installed
    if [ $? -ne 0 ]; then
        log_error "Skipping bindfs test: bindfs not available"
        echo "RESULT:BINDFS:$description:NO_BINDFS" >> "${RESULT_DIR}/bindfs_results.log"
        return 1
    fi
    
    # Prepare mount points
    prepare_bindfs_mounts
    
    # Mount NFS share
    local server_host=$(hostname -f)
    local export_path="${EXPORT_PATH:-/mnt/data-tank/docker}"
    
    log_info "Mounting NFS share with options: $nfs_options"
    ssh_execute_sudo "mount -t nfs$nfs_version -o $nfs_options $server_host:$export_path $nfs_mount"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to mount NFS share"
        echo "RESULT:BINDFS:$description:NFS_MOUNT_FAILED" >> "${RESULT_DIR}/bindfs_results.log"
        return 1
    fi
    
    # Create bindfs mount
    log_info "Creating bindfs mount with options: $bindfs_options"
    ssh_execute_sudo "bindfs $bindfs_options $nfs_mount $bindfs_mount"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create bindfs mount"
        echo "RESULT:BINDFS:$description:BINDFS_MOUNT_FAILED" >> "${RESULT_DIR}/bindfs_results.log"
        
        # Clean up NFS mount
        ssh_unmount "$nfs_mount"
        
        return 1
    fi
    
    # Check content visibility through bindfs
    ssh_get_content_visibility "$bindfs_mount" "${TEST_DIRS[@]}"
    local content_result=$?
    
    # Record result
    if [ $content_result -eq 0 ]; then
        log_success "Bindfs solution successful: $description"
        echo "RESULT:BINDFS:$description:SUCCESS" >> "${RESULT_DIR}/bindfs_results.log"
    elif [ $content_result -eq 2 ]; then
        log_warning "Bindfs solution partially successful: $description"
        echo "RESULT:BINDFS:$description:PARTIAL" >> "${RESULT_DIR}/bindfs_results.log"
    else
        log_error "Bindfs solution failed: $description"
        echo "RESULT:BINDFS:$description:NO_CONTENT" >> "${RESULT_DIR}/bindfs_results.log"
    fi
    
    # Clean up mounts
    ssh_unmount "$bindfs_mount"
    ssh_unmount "$nfs_mount"
    
    return $content_result
}

# Function: test_default_bindfs
# Description: Test bindfs with default options
test_default_bindfs() {
    test_bindfs_solution "Default bindfs" "rw,hard" "--no-allow-other" ""
    return $?
}

# Function: test_user_mapping_bindfs
# Description: Test bindfs with user mapping
test_user_mapping_bindfs() {
    local remote_user="${REMOTE_USER:-joel}"
    test_bindfs_solution "User mapping bindfs" "rw,hard" "--force-user=$remote_user --force-group=$remote_user" ""
    return $?
}

# Function: test_chmod_ignore_bindfs
# Description: Test bindfs with chmod/chown ignore
test_chmod_ignore_bindfs() {
    local remote_user="${REMOTE_USER:-joel}"
    test_bindfs_solution "Chmod ignore bindfs" "rw,hard" "--force-user=$remote_user --force-group=$remote_user --chmod-ignore --chown-ignore" ""
    return $?
}

# Function: test_create_as_user_bindfs
# Description: Test bindfs with create-as-user
test_create_as_user_bindfs() {
    local remote_user="${REMOTE_USER:-joel}"
    test_bindfs_solution "Create as user bindfs" "rw,hard" "--force-user=$remote_user --force-group=$remote_user --create-as-user" ""
    return $?
}

# Function: test_full_bindfs_solution
# Description: Test full recommended bindfs solution
test_full_bindfs_solution() {
    local remote_user="${REMOTE_USER:-joel}"
    test_bindfs_solution "Full bindfs solution" "rw,hard,timeo=600" "--force-user=$remote_user --force-group=$remote_user --create-for-user=root --create-for-group=root --chown-ignore --chmod-ignore" ""
    return $?
}

# Function: create_bindfs_systemd_unit
# Description: Create systemd unit file for successful bindfs configuration
create_bindfs_systemd_unit() {
    local description="$1"
    local nfs_options="$2"
    local bindfs_options="$3"
    local nfs_mount="${REMOTE_NFS_MOUNT:-/mnt/nfs-temp}"
    local final_mount="${REMOTE_BINDFS_MOUNT:-/mnt/bindfs-test}"
    local server_host=$(hostname -f)
    local export_path="${EXPORT_PATH:-/mnt/data-tank/docker}"
    
    log_info "Creating systemd unit files for successful bindfs configuration"
    
    # Create NFS mount unit
    local nfs_unit="[Unit]
Description=Mount NFS Share from TrueNAS
After=network.target

[Mount]
What=${server_host}:${export_path}
Where=${nfs_mount}
Type=nfs
Options=${nfs_options}
TimeoutSec=30

[Install]
WantedBy=multi-user.target"

    # Create bindfs mount unit
    local bindfs_unit="[Unit]
Description=Bindfs mount for Docker directories
After=$(systemd-escape -p --suffix=mount ${nfs_mount})
Requires=$(systemd-escape -p --suffix=mount ${nfs_mount})

[Mount]
What=${nfs_mount}
Where=${final_mount}
Type=fuse.bindfs
Options=${bindfs_options}
TimeoutSec=30

[Install]
WantedBy=multi-user.target"

    # Write the unit files to the results directory
    mkdir -p "${RESULT_DIR}/systemd-units"
    echo "$nfs_unit" > "${RESULT_DIR}/systemd-units/nfs-temp.mount"
    echo "$bindfs_unit" > "${RESULT_DIR}/systemd-units/bindfs-docker.mount"
    
    log_success "Created systemd unit files in ${RESULT_DIR}/systemd-units/"
    echo "RESULT:BINDFS:$description:SYSTEMD_UNITS_CREATED" >> "${RESULT_DIR}/bindfs_results.log"
    
    return 0
}

# Function: test_bindfs_solutions
# Description: Run all bindfs solution tests
test_bindfs_solutions() {
    log_header "Testing bindfs solutions"
    
    # Ensure results directory exists
    mkdir -p "${RESULT_DIR}"
    
    # Run all bindfs tests
    test_default_bindfs
    test_user_mapping_bindfs
    test_chmod_ignore_bindfs
    test_create_as_user_bindfs
    test_full_bindfs_solution
    
    # Create systemd unit file for successful configurations
    if grep -q "RESULT:BINDFS:.*:SUCCESS" "${RESULT_DIR}/bindfs_results.log"; then
        local success_config=$(grep "RESULT:BINDFS:.*:SUCCESS" "${RESULT_DIR}/bindfs_results.log" | head -1)
        local description=$(echo "$success_config" | cut -d: -f3)
        
        # Use the full bindfs solution parameters for the systemd unit
        local remote_user="${REMOTE_USER:-joel}"
        create_bindfs_systemd_unit "$description" "rw,hard,timeo=600" "--force-user=$remote_user --force-group=$remote_user --create-for-user=root --create-for-group=root --chown-ignore --chmod-ignore"
    fi
    
    log_success "All bindfs solutions tested"
    
    # Generate summary
    local success_count=$(grep -c "RESULT:BINDFS:.*:SUCCESS" "${RESULT_DIR}/bindfs_results.log")
    local partial_count=$(grep -c "RESULT:BINDFS:.*:PARTIAL" "${RESULT_DIR}/bindfs_results.log")
    local failed_count=$(grep -c "RESULT:BINDFS:.*:NO_CONTENT\|RESULT:BINDFS:.*:BINDFS_MOUNT_FAILED" "${RESULT_DIR}/bindfs_results.log")
    
    log_info "Summary: $success_count successful, $partial_count partial, $failed_count failed bindfs solutions"
    
    if [ $success_count -gt 0 ]; then
        return 0
    elif [ $partial_count -gt 0 ]; then
        return 2
    else
        return 1
    fi
}

# Execute the main function if this script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    test_bindfs_solutions
fi
