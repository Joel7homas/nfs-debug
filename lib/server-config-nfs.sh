#!/bin/bash
# server-config-nfs.sh - NFS-specific server configuration functions
# Implements the minimalist multi-module pattern (max 10 functions per module)

# Ensure we have core utilities
if ! type log_info &> /dev/null; then
    echo "ERROR: utils-core.sh must be sourced before server-config-nfs.sh"
    exit 1
fi

# Function: update_nfs_export_config
# Description: Update NFS export configuration with specific settings
update_nfs_export_config() {
    local config_name="$1"
    local config_json="$2"
    
    log_info "Updating NFS export configuration: $config_name"
    
    # Get the export ID
    local export_id=$(get_nfs_export_id)
    if [ $? -ne 0 ]; then
        log_error "Failed to get export ID"
        return 1
    fi
    
    # Need to convert export_id to a pure integer
    export_id=$(echo $export_id | tr -d '"' | tr -d ' ')
    
    # Update the security field to match current TrueNAS requirements
    # Replace "security": ["sys"] with "sec": "SYS"
    config_json=$(echo $config_json | sed 's/"security": \["sys"\]/"sec": "SYS"/g')
    
    # Remove any fields that are not expected in current TrueNAS
    config_json=$(echo $config_json | sed 's/"quiet": [^,]*,//g')
    config_json=$(echo $config_json | sed 's/"network": [^,]*,//g')
    config_json=$(echo $config_json | sed 's/"alldirs": [^,]*,//g')
    config_json=$(echo $config_json | sed 's/"root_squash": [^,]*,//g')
    config_json=$(echo $config_json | sed 's/"enabled": [^,]*,//g')
    config_json=$(echo $config_json | sed 's/"ro": [^,]*,//g')
    
    # Update the export configuration
    midclt call "sharing.nfs.update" "$export_id" "$config_json"
    if [ $? -ne 0 ]; then
        log_error "Failed to update NFS export"
        return 1
    fi
    
    log_success "Updated NFS configuration: $config_name"
    
    # Restart NFS service to apply changes
    restart_nfs_service
    
    # Track the configuration change
    echo "CONFIG:NFS:$config_name:$(date +%s)" >> "${RESULT_DIR}/config_changes.log"
    
    return 0
}

# Function: test_nfs_export_config
# Description: Test a specific NFS export configuration
test_nfs_export_config() {
    local config_name="$1"
    local config_json="$2"
    
    log_header "Testing NFS configuration: $config_name"
    
    # Update the export configuration
    update_nfs_export_config "$config_name" "$config_json"
    if [ $? -ne 0 ]; then
        echo "RESULT:NFS:$config_name:ERROR" >> "${RESULT_DIR}/results.log"
        return 1
    fi
    
    # Allow time for changes to take effect
    sleep 3
    
    # Ensure remote mount point exists and is unmounted
    ssh_create_dir "${REMOTE_MOUNT_POINT}"
    ssh_unmount "${REMOTE_MOUNT_POINT}"
    
    # Try to mount
    local server_host=$(hostname -f)
    ssh_execute_sudo "mount -t nfs $server_host:${EXPORT_PATH} ${REMOTE_MOUNT_POINT}"
    local mount_result=$?
    
    if [ $mount_result -ne 0 ]; then
        log_error "Mount failed: $config_name"
        echo "RESULT:NFS:$config_name:MOUNT_FAILED" >> "${RESULT_DIR}/results.log"
        return 1
    fi
    
    # Check content visibility
    ssh_get_content_visibility "${REMOTE_MOUNT_POINT}" "${TEST_DIRS[@]}"
    local content_result=$?
    
    # Unmount
    ssh_unmount "${REMOTE_MOUNT_POINT}"
    
    # Record results
    if [ $content_result -eq 0 ]; then
        log_success "Configuration successful: $config_name"
        echo "RESULT:NFS:$config_name:SUCCESS" >> "${RESULT_DIR}/results.log"
    elif [ $content_result -eq 2 ]; then
        log_warning "Configuration partial: $config_name"
        echo "RESULT:NFS:$config_name:PARTIAL" >> "${RESULT_DIR}/results.log"
    else
        log_error "Configuration failed: $config_name"
        echo "RESULT:NFS:$config_name:FAILED" >> "${RESULT_DIR}/results.log"
    fi
    
    return $content_result
}

# Function: test_no_mapping_config
# Description: Test NFS with no user/group mapping
test_no_mapping_config() {
    local config='{
        "maproot_user": null,
        "maproot_group": null,
        "mapall_user": null,
        "mapall_group": null,
        "security": ["sys"]
    }'
    
    test_nfs_export_config "No mapping" "$config"
    return $?
}

# Function: test_root_mapping_config
# Description: Test NFS with root mapping
test_root_mapping_config() {
    local config='{
        "maproot_user": "root",
        "maproot_group": "wheel",
        "mapall_user": null,
        "mapall_group": null,
        "security": ["sys"]
    }'
    
    test_nfs_export_config "Root mapping" "$config"
    return $?
}

# Function: test_all_root_mapping_config
# Description: Test NFS with all users mapped to root
test_all_root_mapping_config() {
    local config='{
        "maproot_user": null,
        "maproot_group": null,
        "mapall_user": "root",
        "mapall_group": "wheel",
        "security": ["sys"]
    }'
    
    test_nfs_export_config "All to root" "$config"
    return $?
}

# Function: test_remote_user_mapping_config
# Description: Test NFS with mapping to remote user
test_remote_user_mapping_config() {
    local config='{
        "maproot_user": null,
        "maproot_group": null,
        "mapall_user": "'${REMOTE_USER}'",
        "mapall_group": "'${REMOTE_USER}'",
        "security": ["sys"]
    }'
    
    test_nfs_export_config "Map to ${REMOTE_USER}" "$config"
    return $?
}

# Function: test_no_root_squash_config
# Description: Test NFS with no root squashing
test_no_root_squash_config() {
    local config='{
        "maproot_user": null,
        "maproot_group": null,
        "mapall_user": null,
        "mapall_group": null,
        "security": ["sys"],
        "enabled": true,
        "ro": false,
        "quiet": false,
        "network": "*",
        "hosts": [],
        "alldirs": false,
        "root_squash": false
    }'
    
    test_nfs_export_config "No root squash" "$config"
    return $?
}

# Function: test_all_nfs_configs
# Description: Run all NFS configuration tests
test_all_nfs_configs() {
    log_header "Testing all NFS configurations"
    
    # Create results directory
    mkdir -p "${RESULT_DIR}"
    
    # Backup current configuration
    backup_nfs_exports
    
    # Run all the tests
    test_no_mapping_config
    test_root_mapping_config
    test_all_root_mapping_config
    test_remote_user_mapping_config
    test_no_root_squash_config
    
    # Restore the original configuration
    restore_nfs_exports
    
    log_success "All NFS configurations tested"
}

# Execute the main function if this script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    test_all_nfs_configs
fi
