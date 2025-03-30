#!/bin/bash
# server-config-core.sh - Core server configuration functions
# Implements the minimalist multi-module pattern (max 10 functions per module)

# Ensure we have core utilities
if ! type log_info &> /dev/null; then
    echo "ERROR: utils-core.sh must be sourced before server-config-core.sh"
    exit 1
fi

# Function: backup_server_configs
# Description: Backup all server configurations
backup_server_configs() {
    log_info "Backing up all server configurations"
    
    # Make sure we have the backup utilities
    if ! type backup_config &> /dev/null; then
        # Source backup utilities if they're not already available
        source "${LIB_DIR:-./lib}/utils-backup.sh"
    fi
    
    # Backup NFS exports
    backup_nfs_exports
    
    # Backup SMB shares if path exists
    if [ -n "${EXPORT_PATH:-}" ]; then
        backup_smb_shares
    fi
    
    log_success "All server configurations backed up"
    return 0
}

# Function: backup_smb_shares
# Description: Backup SMB share configurations
backup_smb_shares() {
    local export_path="${EXPORT_PATH:-/mnt/data-tank/docker}"
    local query_filter="[[\"path\", \"=\", \"$export_path\"]]"
    
    log_info "Backing up SMB share configurations"
    backup_config "smb-shares" "sharing.smb.query" "$query_filter"
    
    return $?
}

# Function: restore_server_configs
# Description: Restore all server configurations
restore_server_configs() {
    log_info "Restoring all server configurations"
    
    # Make sure we have the backup utilities
    if ! type restore_nfs_exports &> /dev/null; then
        # Source backup utilities if they're not already available
        source "${LIB_DIR:-./lib}/utils-backup.sh"
    fi
    
    # Restore NFS exports
    restore_nfs_exports
    
    # Restore SMB shares if they were backed up
    local smb_backup=$(find_latest_config_backup "smb-shares" 2>/dev/null)
    if [ -n "$smb_backup" ]; then
        restore_smb_shares
    fi
    
    log_success "All server configurations restored"
    return 0
}

# Function: restore_smb_shares
# Description: Restore SMB share configurations
restore_smb_shares() {
    local latest_backup=$(find_latest_config_backup "smb-shares")
    
    if [ -z "$latest_backup" ]; then
        log_warning "No SMB shares backup found"
        return 0
    fi
    
    log_info "Restoring SMB share configurations"
    restore_config "smb-shares" "sharing.smb.query" "$latest_backup"
    
    # Restart SMB service to apply changes
    log_info "Restarting SMB service to apply changes"
    midclt call "service.restart" "cifs"
    
    return $?
}

# Function: restart_nfs_service
# Description: Restart the NFS service
restart_nfs_service() {
    log_info "Restarting NFS service"
    
    # Restart NFS service
    midclt call "service.restart" "nfs"
    local result=$?
    
    if [ $result -eq 0 ]; then
        log_success "NFS service restarted successfully"
    else
        log_error "Failed to restart NFS service"
    fi
    
    # Add a short delay to allow service to fully start
    sleep 3
    
    return $result
}

# Function: restart_smb_service
# Description: Restart the SMB service
restart_smb_service() {
    log_info "Restarting SMB service"
    
    # Restart SMB service
    midclt call "service.restart" "cifs"
    local result=$?
    
    if [ $result -eq 0 ]; then
        log_success "SMB service restarted successfully"
    else
        log_error "Failed to restart SMB service"
    fi
    
    # Add a short delay to allow service to fully start
    sleep 3
    
    return $result
}

# Function: get_nfs_export_id
# Description: Get the ID of the NFS export for a given path
# Returns: Prints the ID to stdout, returns 0 on success, 1 on failure
get_nfs_export_id() {
    local export_path="${EXPORT_PATH:-/mnt/data-tank/docker}"
    
    log_info "Getting NFS export ID for path: $export_path"
    
    # Query for the export
    local export_data=$(midclt call "sharing.nfs.query" "[[\"path\", \"=\", \"$export_path\"]]")
    
    # Check if we got any results
    if [ -z "$export_data" ] || [ "$export_data" == "[]" ]; then
        log_error "No NFS export found for path: $export_path"
        return 1
    fi
    
    # Extract the ID
    local export_id=$(echo "$export_data" | jq -r '.[0].id')
    
    if [ -z "$export_id" ] || [ "$export_id" == "null" ]; then
        log_error "Failed to extract ID from export data"
        return 1
    fi
    
    echo "$export_id"
    return 0
}

# Function: get_smb_share_id
# Description: Get the ID of the SMB share for a given path
# Returns: Prints the ID to stdout, returns 0 on success, 1 on failure
get_smb_share_id() {
    local export_path="${EXPORT_PATH:-/mnt/data-tank/docker}"
    
    log_info "Getting SMB share ID for path: $export_path"
    
    # Query for the share
    local share_data=$(midclt call "sharing.smb.query" "[[\"path\", \"=\", \"$export_path\"]]")
    
    # Check if we got any results
    if [ -z "$share_data" ] || [ "$share_data" == "[]" ]; then
        log_warning "No SMB share found for path: $export_path"
        return 1
    fi
    
    # Extract the ID
    local share_id=$(echo "$share_data" | jq -r '.[0].id')
    
    if [ -z "$share_id" ] || [ "$share_id" == "null" ]; then
        log_error "Failed to extract ID from share data"
        return 1
    fi
    
    echo "$share_id"
    return 0
}

# Function: check_service_status
# Description: Check if a service is running
# Args: $1 - Service name
# Returns: 0 if service is running, 1 otherwise
check_service_status() {
    local service_name="$1"
    
    if [ -z "$service_name" ]; then
        log_error "No service name provided"
        return 1
    fi
    
    log_info "Checking status of service: $service_name"
    
    # Query service status
    local service_status=$(midclt call "service.query" "[[\"service\", \"=\", \"$service_name\"]]")
    
    # Extract running state
    local is_running=$(echo "$service_status" | jq -r '.[0].running')
    
    if [ "$is_running" == "true" ]; then
        log_info "Service $service_name is running"
        return 0
    else
        log_warning "Service $service_name is not running"
        return 1
    fi
}
