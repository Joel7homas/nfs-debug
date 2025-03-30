#!/bin/bash
# server-config-nfs.sh - NFS-specific server configuration functions
# Updated for TrueNAS Scale 24.10.2 API compatibility
# Implements the minimalist multi-module pattern (max 10 functions per module)

# Ensure we have core utilities
if ! type log_info &> /dev/null; then
    echo "ERROR: utils-core.sh must be sourced before server-config-nfs.sh"
    exit 1
fi

# Function: get_existing_nfs_export
# Description: Get existing NFS export if it exists for a path
# Args: $1 - Export path
# Returns: Prints JSON of export if found, empty string if not found
get_existing_nfs_export() {
    local export_path="$1"
    
    log_info "Checking for existing NFS export for path: $export_path"
    
    # Using path (not paths) based on the API documentation and test results
    local result=$(midclt call "sharing.nfs.query" "[[\"path\", \"=\", \"$export_path\"]]")
    
    # Check if we got any results (not empty array)
    if [ "$result" == "[]" ]; then
        echo ""
        return 1
    else
        echo "$result"
        return 0
    fi
}

# Function: create_nfs_export
# Description: Create a new NFS export with specific settings
# Args: $1 - Config name, $2 - Config JSON
create_nfs_export() {
    local config_name="$1"
    local config_json="$2"
    
    log_info "Creating new NFS export: $config_name"
    
    # Create the export - ensure the config_json includes all required fields
    local result=$(midclt call "sharing.nfs.create" "$config_json")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create NFS export: $config_name"
        return 1
    fi
    
    log_success "Created NFS export: $config_name (ID: $result)"
    
    # Restart NFS service to apply changes
    restart_nfs_service
    
    # Track the configuration change
    echo "CONFIG:NFS:$config_name:$(date +%s)" >> "${RESULT_DIR}/config_changes.log"
    
    return 0
}

# Function: update_nfs_export
# Description: Update existing NFS export with specific settings
# Args: $1 - Export ID, $2 - Config name, $3 - Config JSON
update_nfs_export() {
    local export_id="$1"
    local config_name="$2"
    local config_json="$3"
    
    # Validate that export_id is a number
    if ! [[ "$export_id" =~ ^[0-9]+$ ]]; then
        log_error "Invalid export ID: $export_id"
        return 1
    fi
    
    log_info "Updating NFS export (ID: $export_id): $config_name"
    
    # TrueNAS Scale 24.10.2 expects two parameters: id (as integer) and config object
    # Make sure config_json is valid
    if ! jq . <<< "$config_json" > /dev/null 2>&1; then
        log_error "Invalid config JSON: $config_json"
        return 1
    fi
    
    # Execute the update command with proper ID handling
    midclt call "sharing.nfs.update" "$export_id" "$config_json"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to update NFS export: $config_name"
        return 1
    fi
    
    log_success "Updated NFS export: $config_name"
    
    # Restart NFS service to apply changes
    restart_nfs_service
    
    # Track the configuration change
    echo "CONFIG:NFS:$config_name:$(date +%s)" >> "${RESULT_DIR}/config_changes.log"
    
    return 0
}

# Function: delete_nfs_export
# Description: Delete an NFS export
# Args: $1 - Export ID
delete_nfs_export() {
    local export_id="$1"
    
    log_info "Deleting NFS export (ID: $export_id)"
    
    # Delete the export
    midclt call "sharing.nfs.delete" "$export_id"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to delete NFS export"
        return 1
    fi
    
    log_success "Deleted NFS export"
    
    # Restart NFS service to apply changes
    restart_nfs_service
    
    return 0
}

# Function: configure_nfs_export
# Description: Configure NFS export (create or update as needed)
# Args: $1 - Config name, $2 - Config JSON
configure_nfs_export() {
    local config_name="$1"
    local config_json="$2"
    
    log_info "Configuring NFS export: $config_name"
    
    # Extract path from the config JSON
    local export_path=$(echo "$config_json" | jq -r '.path')
    
    # Check if export already exists
    local existing_export=$(get_existing_nfs_export "$export_path")
    
    if [ -n "$existing_export" ]; then
        # Extract ID from existing export
        local export_id=$(echo "$existing_export" | jq -r '.[0].id')
        
        # Update existing export
        update_nfs_export "$export_id" "$config_name" "$config_json"
        return $?
    else
        # Create new export
        create_nfs_export "$config_name" "$config_json"
        return $?
    fi
}

# Function: test_nfs_export_config
# Description: Test a specific NFS export configuration
# Args: $1 - Config name, $2 - Config JSON
test_nfs_export_config() {
    local config_name="$1"
    local config_json="$2"
    
    log_header "Testing NFS configuration: $config_name"
    
    # Configure the export
    configure_nfs_export "$config_name" "$config_json"
    if [ $? -ne 0 ]; then
        echo "RESULT:NFS:$config_name:ERROR" >> "${RESULT_DIR}/results.log"
        return 1
    fi
    
    # Allow time for changes to take effect
    sleep 3
    
    # Ensure remote mount point exists and is unmounted
    ssh_create_dir "${REMOTE_MOUNT_POINT}"
    ssh_unmount "${REMOTE_MOUNT_POINT}"
    
    # Extract path from config
    local export_path=$(echo "$config_json" | jq -r '.path')
    
    # Try to mount
    local server_host=$(hostname -f)
    ssh_execute_sudo "mount -t nfs $server_host:$export_path ${REMOTE_MOUNT_POINT}"
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
    
    # Restore original configuration
    # This would typically call restore_nfs_exports but since we're
    # creating a temporary export, we'll handle cleanup differently
    
    # First get the export ID
    local export_path=$(echo "$config_json" | jq -r '.path')
    local existing_export=$(get_existing_nfs_export "$export_path")
    
    if [ -n "$existing_export" ]; then
        local export_id=$(echo "$existing_export" | jq -r '.[0].id')
        # Instead of deleting, we'll restore from backup if available
        # This ensures we don't lose original configuration
        local backup_found=false
        
        # Attempt to restore from backup
        if type restore_nfs_exports &> /dev/null; then
            restore_nfs_exports
            backup_found=true
        fi
        
        # If no backup restoration function is available, delete the test export
        if [ "$backup_found" != "true" ]; then
            log_warning "No backup restoration function found, deleting test export"
            delete_nfs_export "$export_id"
        fi
    fi
    
    return $content_result
}

# Function: get_basic_nfs_config
# Description: Get a basic NFS export configuration template
# Args: $1 - Export path, $2 - Optional additional JSON fields
# Returns: Prints complete JSON configuration
get_basic_nfs_config() {
    local export_path="$1"
    local additional_fields="${2:-{}}"
    
    # Create base config with current TrueNAS API format based on sample output
    local base_config="{
        \"path\": \"$export_path\",
        \"comment\": \"Temporary test export\",
        \"hosts\": [\"192.168.4.99\"],
        \"ro\": false,
        \"enabled\": true,
        \"networks\": []
    }"
    
    # Validate base config
    if ! jq . <<< "$base_config" > /dev/null 2>&1; then
        log_error "Invalid base NFS JSON configuration"
        return 1
    fi
    
    # Validate additional fields
    if ! jq . <<< "$additional_fields" > /dev/null 2>&1; then
        log_error "Invalid additional NFS fields: $additional_fields"
        return 1
    fi
    
    # Merge configs safely
    local merged_config
    merged_config=$(jq -s '.[0] * .[1]' <<< "$base_config" <<< "$additional_fields" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$merged_config" ]; then
        log_error "Failed to merge NFS JSON configurations"
        echo "$base_config"
        return 1
    fi
    
    echo "$merged_config"
    return 0
}

# Function: test_no_mapping_config
# Description: Test NFS with no user/group mapping
test_no_mapping_config() {
    local export_path="${EXPORT_PATH:-/mnt/data-tank/docker}"
    
    local additional_fields='{
        "maproot_user": null,
        "maproot_group": null,
        "mapall_user": null,
        "mapall_group": null,
        "security": []
    }'
    
    local config_json
    config_json=$(get_basic_nfs_config "$export_path" "$additional_fields")
    
    # Check if get_basic_nfs_config succeeded
    if [ $? -ne 0 ]; then
        log_error "Failed to generate NFS config for No mapping test"
        return 1
    fi
    
    # Validate JSON
    if ! jq . <<< "$config_json" > /dev/null 2>&1; then
        log_error "Invalid JSON configuration for No mapping test"
        return 1
    fi
    
    test_nfs_export_config "No mapping" "$config_json"
    return $?
}

# Function: test_root_mapping_config
# Description: Test NFS with root mapping
test_root_mapping_config() {
    local export_path="${EXPORT_PATH:-/mnt/data-tank/docker}"
    
    local additional_fields='{
        "maproot_user": "root",
        "maproot_group": "wheel",
        "mapall_user": null,
        "mapall_group": null,
        "security": ["SYS"]
    }'
    
    local config_json
    config_json=$(get_basic_nfs_config "$export_path" "$additional_fields")
    
    # Check if get_basic_nfs_config succeeded
    if [ $? -ne 0 ]; then
        log_error "Failed to generate NFS config for Root mapping test"
        return 1
    fi
    
    # Validate JSON
    if ! jq . <<< "$config_json" > /dev/null 2>&1; then
        log_error "Invalid JSON configuration for Root mapping test"
        return 1
    fi
    
    test_nfs_export_config "Root mapping" "$config_json"
    return $?
}

# Function: test_all_root_mapping_config
# Description: Test NFS with all users mapped to root
test_all_root_mapping_config() {
    local export_path="${EXPORT_PATH:-/mnt/data-tank/docker}"
    
    local additional_fields='{
        "maproot_user": null,
        "maproot_group": null,
        "mapall_user": "root",
        "mapall_group": "wheel",
        "security": ["SYS"]
    }'
    
    local config_json
    config_json=$(get_basic_nfs_config "$export_path" "$additional_fields")
    
    # Check if get_basic_nfs_config succeeded
    if [ $? -ne 0 ]; then
        log_error "Failed to generate NFS config for All to root test"
        return 1
    fi
    
    # Validate JSON
    if ! jq . <<< "$config_json" > /dev/null 2>&1; then
        log_error "Invalid JSON configuration for All to root test"
        return 1
    fi
    
    test_nfs_export_config "All to root" "$config_json"
    return $?
}

# Function: test_remote_user_mapping_config
# Description: Test NFS with mapping to remote user
test_remote_user_mapping_config() {
    local export_path="${EXPORT_PATH:-/mnt/data-tank/docker}"
    local remote_user="${REMOTE_USER:-joel}"
    
    # Create the JSON with proper escaping
    local additional_fields="{
        \"maproot_user\": null,
        \"maproot_group\": null,
        \"mapall_user\": \"$remote_user\",
        \"mapall_group\": \"$remote_user\",
        \"security\": [\"SYS\"]
    }"
    
    local config_json
    config_json=$(get_basic_nfs_config "$export_path" "$additional_fields")
    
    # Check if get_basic_nfs_config succeeded
    if [ $? -ne 0 ]; then
        log_error "Failed to generate NFS config for Map to user test"
        return 1
    fi
    
    # Validate JSON
    if ! jq . <<< "$config_json" > /dev/null 2>&1; then
        log_error "Invalid JSON configuration for Map to user test"
        return 1
    fi
    
    test_nfs_export_config "Map to ${REMOTE_USER}" "$config_json"
    return $?
}

# Function: test_all_nfs_configs
# Description: Run all NFS configuration tests
test_all_nfs_configs() {
    log_header "Testing all NFS configurations"
    
    # Create results directory
    mkdir -p "${RESULT_DIR}"
    
    # Run all the tests
    test_no_mapping_config
    test_root_mapping_config
    test_all_root_mapping_config
    test_remote_user_mapping_config
    
    log_success "All NFS configurations tested"
}

# Execute the main function if this script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    test_all_nfs_configs
fi
