#!/bin/bash
# patch-mount.sh - Patches for mount/unmount commands in original scripts
# Implements the minimalist multi-module pattern (max 10 functions per module)

# Ensure we have core utilities
if ! type log_info &> /dev/null; then
    echo "ERROR: utils-core.sh must be sourced before patch-mount.sh"
    exit 1
fi

# Function: ensure_patch_dirs
# Description: Create patch directories if they don't exist
ensure_patch_dirs() {
    local patched_dir="${PATCHED_DIR:-./patched}"
    local original_dir="${ORIGINAL_DIR:-./original}"
    
    log_info "Ensuring patch directories exist"
    
    if [ ! -d "$original_dir" ]; then
        log_error "Original scripts directory not found: $original_dir"
        return 1
    fi
    
    mkdir -p "$patched_dir"
    
    if [ -d "$patched_dir" ]; then
        log_success "Patch directories ready"
        return 0
    else
        log_error "Failed to create patched scripts directory"
        return 1
    fi
}

# Function: copy_originals
# Description: Copy original scripts to patch directory
copy_originals() {
    local patched_dir="${PATCHED_DIR:-./patched}"
    local original_dir="${ORIGINAL_DIR:-./original}"
    
    log_info "Copying original scripts to patch directory"
    
    for script in "$original_dir"/*.sh; do
        if [ -f "$script" ]; then
            local base_name=$(basename "$script")
            cp "$script" "$patched_dir/$base_name"
            
            if [ $? -eq 0 ]; then
                log_info "Copied $base_name to patch directory"
            else
                log_error "Failed to copy $base_name"
                return 1
            fi
        fi
    done
    
    log_success "Copied original scripts to patch directory"
    return 0
}

# Function: patch_mount_commands
# Description: Patch mount commands in a script to run via SSH
patch_mount_commands() {
    local script="$1"
    
    if [ ! -f "$script" ]; then
        log_error "Script file not found: $script"
        return 1
    fi
    
    log_info "Patching mount commands in $script"
    
    # Patch NFSv3 and NFSv4 mount commands
    sed -i 's/sudo mount -t "nfs/ssh "${REMOTE_USER}@${REMOTE_HOST}" "sudo mount -t nfs/g' "$script"
    sed -i 's/sudo mount -t "nfs4/ssh "${REMOTE_USER}@${REMOTE_HOST}" "sudo mount -t nfs4/g' "$script"
    
    # Patch generic mount commands
    sed -i 's/sudo mount -o/ssh "${REMOTE_USER}@${REMOTE_HOST}" "sudo mount -o/g' "$script"
    sed -i 's/sudo mount --bind/ssh "${REMOTE_USER}@${REMOTE_HOST}" "sudo mount --bind/g' "$script"
    
    log_success "Patched mount commands in $script"
    return 0
}

# Function: patch_unmount_commands
# Description: Patch unmount commands in a script to run via SSH
patch_unmount_commands() {
    local script="$1"
    
    if [ ! -f "$script" ]; then
        log_error "Script file not found: $script"
        return 1
    fi
    
    log_info "Patching unmount commands in $script"
    
    # Patch umount commands (careful with patterns to avoid infinite substitution)
    sed -i 's/sudo umount /ssh "${REMOTE_USER}@${REMOTE_HOST}" "sudo umount /g' "$script"
    
    # Fix double quotes at the end of lines
    sed -i 's/"sudo umount \([^"]*\)$/"sudo umount \1"/g' "$script"
    
    log_success "Patched unmount commands in $script"
    return 0
}

# Function: patch_directory_commands
# Description: Patch directory commands in a script to run via SSH
patch_directory_commands() {
    local script="$1"
    
    if [ ! -f "$script" ]; then
        log_error "Script file not found: $script"
        return 1
    fi
    
    log_info "Patching directory commands in $script"
    
    # Patch mkdir and rmdir commands
    sed -i 's/sudo mkdir -p /ssh "${REMOTE_USER}@${REMOTE_HOST}" "sudo mkdir -p /g' "$script"
    sed -i 's/sudo rmdir /ssh "${REMOTE_USER}@${REMOTE_HOST}" "sudo rmdir /g' "$script"
    
    # Fix double quotes at the end of lines
    sed -i 's/"sudo mkdir -p \([^"]*\)$/"sudo mkdir -p \1"/g' "$script"
    sed -i 's/"sudo rmdir \([^"]*\)$/"sudo rmdir \1"/g' "$script"
    
    log_success "Patched directory commands in $script"
    return 0
}

# Function: apply_mount_patches
# Description: Apply all mount-related patches to scripts
apply_mount_patches() {
    ensure_patch_dirs || return 1
    copy_originals || return 1
    
    local patched_dir="${PATCHED_DIR:-./patched}"
    
    for script in "$patched_dir"/*.sh; do
        if [ -f "$script" ]; then
            patch_mount_commands "$script"
            patch_unmount_commands "$script"
            patch_directory_commands "$script"
        fi
    done
    
    log_success "All mount-related commands patched"
    return 0
}

# Execute the main function if this script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    apply_mount_patches
fi
