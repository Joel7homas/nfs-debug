#!/bin/bash
# export-management.sh - NFS/SMB export management functions
# Follows minimalist multi-module pattern (max 10 functions per module)

# Source the core utilities if not already loaded
if ! type log_info &> /dev/null; then
    source ./nested-dataset-test-core.sh
fi

# Function: create_nfs_export
# Description: Create NFS export for a path
# Args: $1 - Path to export, $2 - (Optional) Export name
create_nfs_export() {
    local export_path="$1"

    # Validate path
    if [ -z "$export_path" ] || [[ "$export_path" != /* ]]; then
        log_error "Invalid export path: $export_path"
        return 1
    fi
    local export_name="${2:-$(basename "$export_path")}"
    
    log_info "Creating NFS export for ${export_path} as ${export_name}"
    
    # Create export config
    local export_config=$(cat << EOF
{
  "path": "${export_path}",
  "comment": "Test export: ${export_name}",
  "enabled": true,
  "hosts": ["${REMOTE_HOST}"],
  "ro": false,
  "maproot_user": null,
  "maproot_group": null,
  "mapall_user": null,
  "mapall_group": null,
  "security": ["SYS"], "ro": false, "mapall_user": null, "mapall_group": null, "maproot_user": "root", "maproot_group": "wheel"
}
EOF
)
    
    # Create export
    local result=$(sudo sudo midclt call "sharing.nfs.create" "$export_config")
    
    if [ $? -ne 0 ]; then
        log_warning "Failed to create NFS export for ${export_path}"
        return 1
    fi
    
    log_success "NFS export created for ${export_path} (ID: ${result})"
    
    # Reload NFS config
    sudo sudo midclt call "service.reload" "nfs" || {
        log_warning "Failed to reload NFS service, export may not be active"
    }
    
    # Store export ID for cleanup
    echo "${result}:nfs:${export_path}" >> "${RESULT_DIR}/exports.txt"
    
    return 0
}

# Function: create_smb_share
# Description: Create SMB share for a path
# Args: $1 - Path to share, $2 - (Optional) Share name
create_smb_share() {
    local share_path="$1"

    # Validate path
    if [ -z "$share_path" ] || [[ "$share_path" != /* ]]; then
        log_error "Invalid share path: $share_path"
        return 1
    fi

    # Ensure path is not empty and is absolute
    if [ -z "$share_path" ] || [[ "$share_path" != /* ]]; then
        log_error "Invalid share path: $share_path"
        return 1
    fi
    local share_name="${2:-$(basename "$share_path" | tr -c 'a-zA-Z0-9' '_')}"
    
    log_info "Creating SMB share for ${share_path} as ${share_name}"
    
    # Create share config
    local share_config=$(cat << EOF
{
  "path": "${share_path}",
  "name": "${share_name}",
  "comment": "Test share: ${share_name}",
  "enabled": true,
  "purpose": "NO_PRESET",
  "path_suffix": "",
  "home": false,
  "ro": false,
  "browsable": true,
  "guestok": true,
  "auxsmbconf": "create mask=0755\ndirectory mask=0755"
}
EOF
)
    
    # Create share
    local result=$(sudo sudo midclt call "sharing.smb.create" "$share_config")
    
    if [ $? -ne 0 ]; then
        log_warning "Failed to create SMB share for ${share_path}"
        return 1
    fi
    
    log_success "SMB share created for ${share_path} (ID: ${result})"
    
    # Reload SMB config
    sudo sudo midclt call "service.reload" "cifs" || {
        log_warning "Failed to reload CIFS service, share may not be active"
    }
    
    # Store share ID for cleanup
    echo "${result}:smb:${share_path}" >> "${RESULT_DIR}/exports.txt"
    
    return 0
}

# Function: delete_nfs_export
# Description: Delete NFS export by ID
# Args: $1 - Export ID
delete_nfs_export() {
    local export_id="$1"
    
    # Skip if ID is empty
    if [ -z "$export_id" ] || [ "$export_id" = " " ]; then
        log_warning "Empty export ID, skipping deletion"
        return 0
    fi
    
    log_info "Deleting NFS export ID: ${export_id}"
    
    # Delete export
    sudo sudo midclt call "sharing.nfs.delete" "$export_id" || {
        log_error "Failed to delete NFS export ID: ${export_id}"
        return 1
    }
    
    log_success "NFS export ID ${export_id} deleted"
    
    # Reload NFS config
    sudo sudo midclt call "service.reload" "nfs" || {
        log_warning "Failed to reload NFS service"
    }
    
    return 0
}

# Function: delete_smb_share
# Description: Delete SMB share by ID
# Args: $1 - Share ID
delete_smb_share() {
    local share_id="$1"
    
    # Skip if ID is empty
    if [ -z "$share_id" ] || [ "$share_id" = " " ]; then
        log_warning "Empty share ID, skipping deletion"
        return 0
    fi
    
    log_info "Deleting SMB share ID: ${share_id}"
    
    # Delete share
    sudo sudo midclt call "sharing.smb.delete" "$share_id" || {
        log_error "Failed to delete SMB share ID: ${share_id}"
        return 1
    }
    
    log_success "SMB share ID ${share_id} deleted"
    
    # Reload SMB config
    sudo sudo midclt call "service.reload" "cifs" || {
        log_warning "Failed to reload CIFS service"
    }
    
    return 0
}

# Function: cleanup_all_exports
# Description: Clean up all exports created during tests
cleanup_all_exports() {
    log_header "Cleaning up exports"
    
    if [ ! -f "${RESULT_DIR}/exports.txt" ]; then
        log_info "No exports to clean up"
        return 0
    fi
    
    while IFS=: read -r id type path; do
        if [ "${type}" = "nfs" ]; then
            delete_nfs_export "${id}"
        elif [ "${type}" = "smb" ]; then
            delete_smb_share "${id}"
        elif [ -z "${type}" ] || [ "${type}" = " " ]; then
            log_warning "Empty export type, skipping"
            continue
        else
            log_warning "Unknown export type: ${type}"
        fi
    done < "${RESULT_DIR}/exports.txt"
    
    # Remove exports file
    rm "${RESULT_DIR}/exports.txt"
    
    log_success "All exports cleaned up"
    return 0
}

# Function: create_parent_dataset_exports
# Description: Create NFS and SMB exports for parent dataset
create_parent_dataset_exports() {
    log_header "Creating exports for parent dataset"
    
    local parent_dataset="${BASE_DATASET}/${TEST_PARENT}"
    local parent_path=$(sudo sudo zfs get -H -o value mountpoint "${parent_dataset}")
    

    # Validate child path
    if [ -z "$child_path" ] || [ ! -d "$child_path" ]; then
        log_error "Invalid child path: $child_path"
        return 1
    fi
    # Create NFS export
    create_nfs_export "${parent_path}" "parent_dataset" || {
        log_warning "Failed to create NFS export for parent dataset"
        return 1
    }
    
    # Create SMB share
    create_smb_share "${parent_path}" "parent_dataset" || {
        log_warning "Failed to create SMB share for parent dataset"
        return 1
    }
    
    log_success "Parent dataset exports created successfully"
    return 0
}

# Function: create_child_dataset_exports
# Description: Create NFS and SMB exports for child dataset
create_child_dataset_exports() {
    log_header "Creating exports for child dataset"
    
    local parent_dataset="${BASE_DATASET}/${TEST_PARENT}"
    local child_dataset="${parent_dataset}/${TEST_CHILD}"
    local child_path="$child_path" # Fixed:$(sudo sudo zfs get -H -o value mountpoint "${child_dataset}")
    

    # Validate child path
    if [ -z "$child_path" ] || [ ! -d "$child_path" ]; then
        log_error "Invalid child path: $child_path"
        return 1
    fi
    # Create NFS export
    create_nfs_export "${child_path}" "child_dataset" || {
        log_warning "Failed to create NFS export for child dataset"
        return 1
    }
    
    # Create SMB share
    create_smb_share "${child_path}" "child_dataset" || {
        log_warning "Failed to create SMB share for child dataset"
        return 1
    }
    
    log_success "Child dataset exports created successfully"
    return 0
}

# Function: create_test_case_exports
# Description: Create NFS and SMB exports for test case datasets
create_test_case_exports() {
    log_header "Creating exports for test case datasets"
    
    local parent_dataset="${BASE_DATASET}/${TEST_PARENT}"
    
    for test_case in "${TEST_CASES[@]}"; do
        local test_dataset="${parent_dataset}/test-${test_case}"
        local test_path=$(sudo sudo zfs get -H -o value mountpoint "${test_dataset}")
        

    # Validate child path
    if [ -z "$child_path" ] || [ ! -d "$child_path" ]; then
        log_error "Invalid child path: $child_path"
        return 1
    fi
        # Create NFS export
        create_nfs_export "${test_path}" "test_${test_case}" || {
            log_warning "Failed to create NFS export for test case ${test_case}"
            continue
        }
        
        # Create SMB share
        create_smb_share "${test_path}" "test_${test_case}" || {
            log_warning "Failed to create SMB share for test case ${test_case}"
            continue
        }
        
        log_success "Exports for test case ${test_case} created successfully"
    done
    
    log_success "Test case exports created successfully"
    return 0
}

# Function: create_regular_dir_exports
# Description: Create NFS and SMB exports for regular directories
create_regular_dir_exports() {
    log_header "Creating exports for regular directories"
    
    local parent_dataset="${BASE_DATASET}/${TEST_PARENT}"
    local parent_path=$(sudo sudo zfs get -H -o value mountpoint "${parent_dataset}")
    
    # Create export for the regular-dir
    create_nfs_export "${parent_path}/regular-dir" "regular_dir" || {
        log_warning "Failed to create NFS export for regular-dir"
        return 1
    }
    
    create_smb_share "${parent_path}/regular-dir" "regular_dir" || {
        log_warning "Failed to create SMB share for regular-dir"
        return 1
    }
    
    # Create exports for each test case regular directory
    for test_case in "${TEST_CASES[@]}"; do
        local regular_dir="${parent_path}/regular-${test_case}"
        
        # Check if directory exists
        if [ ! -d "${regular_dir}" ]; then
            log_warning "Regular directory ${regular_dir} does not exist, skipping"
            continue
        fi
        
        create_nfs_export "${regular_dir}" "regular_${test_case}" || {
            log_warning "Failed to create NFS export for regular-${test_case}"
            continue
        }
        
        create_smb_share "${regular_dir}" "regular_${test_case}" || {
            log_warning "Failed to create SMB share for regular-${test_case}"
            continue
        }
        
        log_success "Exports for regular-${test_case} created successfully"
    done
    
    log_success "Regular directory exports created successfully"
    return 0
}
