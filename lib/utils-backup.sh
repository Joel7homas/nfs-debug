#!/bin/bash
# utils-backup.sh - Backup and restore utilities for NFS testing
# Updated for TrueNAS Scale 24.10.2 API compatibility
# Implements the minimalist multi-module pattern (max 10 functions per module)

# Ensure we have core utilities
if ! type log_info &> /dev/null; then
    echo "ERROR: utils-core.sh must be sourced before utils-backup.sh"
    exit 1
fi

# Function: ensure_backup_dir
# Description: Ensure backup directory exists
# Returns: 0 on success, 1 on failure
ensure_backup_dir() {
    local backup_dir="${BACKUP_DIR:-./backups}"
    
    log_info "Ensuring backup directory exists: $backup_dir"
    mkdir -p "$backup_dir"
    
    if [ -d "$backup_dir" ]; then
        log_success "Backup directory ready: $backup_dir"
        return 0
    else
        log_error "Failed to create backup directory: $backup_dir"
        return 1
    fi
}

# Function: backup_file
# Description: Create a backup of a file with timestamp
# Args: $1 - File to backup
# Returns: 0 on success, 1 on failure
backup_file() {
    local file="$1"
    local backup_dir="${BACKUP_DIR:-./backups}"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local filename=$(basename "$file")
    local backup_file="$backup_dir/${filename}.${timestamp}.bak"
    
    # Ensure backup directory exists
    ensure_backup_dir
    
    if [ ! -f "$file" ]; then
        log_error "File does not exist: $file"
        return 1
    fi
    
    log_info "Creating backup of $file to $backup_file"
    cp "$file" "$backup_file"
    
    if [ -f "$backup_file" ]; then
        log_success "Backup created: $backup_file"
        return 0
    else
        log_error "Failed to create backup: $backup_file"
        return 1
    fi
}

# Function: restore_file
# Description: Restore a file from its most recent backup
# Args: $1 - Original file path
# Returns: 0 on success, 1 on failure
restore_file() {
    local file="$1"
    local backup_dir="${BACKUP_DIR:-./backups}"
    local filename=$(basename "$file")
    
    # Find the most recent backup
    local latest_backup=$(ls -t "$backup_dir/${filename}".*.bak 2>/dev/null | head -n 1)
    
    if [ -z "$latest_backup" ]; then
        log_error "No backup found for $file"
        return 1
    fi
    
    log_info "Restoring $file from $latest_backup"
    cp "$latest_backup" "$file"
    
    if [ $? -eq 0 ]; then
        log_success "File restored: $file"
        return 0
    else
        log_error "Failed to restore file: $file"
        return 1
    fi
}

# Function: backup_config
# Description: Backup a configuration using TrueNAS API
# Args: $1 - Config name, $2 - API endpoint, $3 - Query filter
# Returns: 0 on success, 1 on failure
backup_config() {
    local config_name="$1"
    local api_endpoint="$2"
    local query_filter="$3"
    local backup_dir="${BACKUP_DIR:-./backups}"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="$backup_dir/${config_name}-${timestamp}.json"
    
    # Ensure backup directory exists
    ensure_backup_dir
    
    log_info "Backing up $config_name configuration"
    midclt call "$api_endpoint" "$query_filter" > "$backup_file"
    
    if [ -f "$backup_file" ] && [ -s "$backup_file" ]; then
        log_success "$config_name configuration backed up to $backup_file"
        echo "$config_name:$api_endpoint:$backup_file" >> "$backup_dir/backup_registry.txt"
        return 0
    else
        log_error "Failed to backup $config_name configuration"
        return 1
    fi
}

# Function: restore_config
# Description: Restore a configuration using TrueNAS API
# Args: $1 - Config name, $2 - API endpoint, $3 - Backup file path
# Returns: 0 on success, 1 on failure
restore_config() {
    local config_name="$1"
    local api_endpoint="$2"
    local backup_file="$3"
    
    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    log_info "Restoring $config_name configuration from $backup_file"
    
    # Get the array of configurations from the backup file
    local configs=$(cat "$backup_file")
    
    # If it's an empty array, nothing to restore
    if [ "$configs" == "[]" ]; then
        log_warning "No configurations to restore from backup"
        return 0
    fi
    
    # Process each configuration in the array
    echo "$configs" | jq -c '.[]' | while read -r config; do
        # Get the ID from the config
        local id=$(echo "$config" | jq -r '.id')
        if [ -z "$id" ] || [ "$id" == "null" ]; then
            log_error "Failed to extract ID from config"
            continue
        fi
        
        # Sanitize the config by removing fields that cause errors
        # This fixes: [EINVAL] sharingnfs_update.id: Field was not expected
        local update_endpoint="${api_endpoint%.query}.update"
        
        # Different sanitization based on endpoint type
        if [[ "$update_endpoint" == *"nfs"* ]]; then
            # For NFS exports, remove problematic fields
            local sanitized=$(echo "$config" | jq 'del(.id, .locked)')
        elif [[ "$update_endpoint" == *"smb"* ]]; then
            # For SMB shares, remove problematic fields
            local sanitized=$(echo "$config" | jq 'del(.id, .locked, .vuid, .path_local)')
        else
            # Default sanitization
            local sanitized=$(echo "$config" | jq 'del(.id, .locked)')
        fi
        
        # Update the configuration
        midclt call "$update_endpoint" "$id" "$sanitized"
        
        if [ $? -ne 0 ]; then
            log_error "Failed to restore configuration with ID $id"
        else
            log_success "Restored configuration with ID $id"
        fi
    done
    
    log_success "$config_name configuration restored"
    return 0
}

# Function: find_latest_config_backup
# Description: Find the latest backup file for a specific configuration
# Args: $1 - Config name
# Returns: Prints the path to the latest backup file
find_latest_config_backup() {
    local config_name="$1"
    local backup_dir="${BACKUP_DIR:-./backups}"
    
    local latest_backup=$(ls -t "$backup_dir/${config_name}"-*.json 2>/dev/null | head -n 1)
    
    if [ -z "$latest_backup" ]; then
        log_error "No backup found for $config_name"
        return 1
    fi
    
    echo "$latest_backup"
    return 0
}

# Function: backup_nfs_exports
# Description: Backup all NFS exports
# Returns: 0 on success, 1 on failure
backup_nfs_exports() {
    local export_path="${EXPORT_PATH:-/mnt/data-tank/docker}"
    # Using correct path filter format for TrueNAS Scale 24.10.2
    local query_filter="[[\"path\", \"=\", \"$export_path\"]]"
    
    log_info "Backing up NFS export configurations"
    backup_config "nfs-exports" "sharing.nfs.query" "$query_filter"
    return $?
}

# Function: restore_nfs_exports
# Description: Restore NFS exports from the latest backup
# Returns: 0 on success, 1 on failure
restore_nfs_exports() {
    local latest_backup=$(find_latest_config_backup "nfs-exports")
    
    if [ -z "$latest_backup" ]; then
        return 1
    fi
    
    log_info "Restoring nfs-exports configuration from $latest_backup"
    restore_config "nfs-exports" "sharing.nfs.query" "$latest_backup"
    
    # Restart NFS service to apply changes
    log_info "Restarting NFS service to apply changes"
    midclt call "service.restart" "nfs"
    
    return $?
}

# Function: restore_all_backups
# Description: Restore all backed up configurations
# Returns: 0 on success, 1 on failure
restore_all_backups() {
    local backup_dir="${BACKUP_DIR:-./backups}"
    local registry_file="$backup_dir/backup_registry.txt"
    local failures=0
    
    if [ ! -f "$registry_file" ]; then
        log_warning "No backup registry found. Nothing to restore."
        return 0
    fi
    
    log_info "Restoring all backed up configurations"
    
    while IFS=: read -r config_name api_endpoint backup_file; do
        log_info "Restoring $config_name from $backup_file"
        restore_config "$config_name" "$api_endpoint" "$backup_file"
        
        if [ $? -ne 0 ]; then
            failures=$((failures + 1))
        fi
    done < "$registry_file"
    
    if [ $failures -eq 0 ]; then
        log_success "All configurations restored successfully"
        return 0
    else
        log_error "$failures restoration(s) failed"
        return 1
    fi
}
