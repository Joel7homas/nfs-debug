#!/bin/bash
# utils-ssh.sh - SSH utility functions for remote execution
# Implements the minimalist multi-module pattern (max 10 functions per module)

# Ensure we have core utilities
if ! type log_info &> /dev/null; then
    echo "ERROR: utils-core.sh must be sourced before utils-ssh.sh"
    exit 1
fi

# Function: ssh_execute
# Description: Execute a command on remote host
# Args: $1 - Command to execute
# Returns: Exit code from remote command
ssh_execute() {
    local command="$1"
    
    if [ -z "${REMOTE_HOST}" ] || [ -z "${REMOTE_USER}" ]; then
        log_error "Remote host or user not defined"
        return 1
    fi
    
    log_info "Executing on ${REMOTE_HOST}: $command"
    ssh "${REMOTE_USER}@${REMOTE_HOST}" "$command"
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log_success "Remote command executed successfully"
    else
        log_error "Remote command failed with exit code $exit_code"
    fi
    
    return $exit_code
}

# Function: ssh_execute_sudo
# Description: Execute a command on remote host with sudo
# Args: $1 - Command to execute
# Returns: Exit code from remote command
ssh_execute_sudo() {
    local command="$1"
    
    if [ -z "${REMOTE_HOST}" ] || [ -z "${REMOTE_USER}" ]; then
        log_error "Remote host or user not defined"
        return 1
    fi
    
    log_info "Executing with sudo on ${REMOTE_HOST}: $command"
    ssh "${REMOTE_USER}@${REMOTE_HOST}" "sudo $command"
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log_success "Remote sudo command executed successfully"
    else
        log_error "Remote sudo command failed with exit code $exit_code"
    fi
    
    return $exit_code
}

# Function: ssh_copy_file
# Description: Copy a file to the remote host
# Args: $1 - Local file path, $2 - Remote file path
# Returns: Exit code from scp command
ssh_copy_file() {
    local local_file="$1"
    local remote_file="$2"
    
    if [ -z "${REMOTE_HOST}" ] || [ -z "${REMOTE_USER}" ]; then
        log_error "Remote host or user not defined"
        return 1
    fi
    
    if [ ! -f "$local_file" ]; then
        log_error "Local file not found: $local_file"
        return 1
    fi
    
    log_info "Copying file to ${REMOTE_HOST}: $local_file -> $remote_file"
    scp "$local_file" "${REMOTE_USER}@${REMOTE_HOST}:$remote_file"
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log_success "File copied successfully"
    else
        log_error "File copy failed with exit code $exit_code"
    fi
    
    return $exit_code
}

# Function: ssh_check_dir
# Description: Check if a directory exists on remote host
# Args: $1 - Directory path to check
# Returns: 0 if directory exists, 1 otherwise
ssh_check_dir() {
    local remote_dir="$1"
    
    if [ -z "${REMOTE_HOST}" ] || [ -z "${REMOTE_USER}" ]; then
        log_error "Remote host or user not defined"
        return 1
    fi
    
    log_info "Checking if directory exists on ${REMOTE_HOST}: $remote_dir"
    ssh "${REMOTE_USER}@${REMOTE_HOST}" "[ -d \"$remote_dir\" ]"
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log_info "Directory exists: $remote_dir"
    else
        log_info "Directory does not exist: $remote_dir"
    fi
    
    return $exit_code
}

# Function: ssh_create_dir
# Description: Create a directory on remote host
# Args: $1 - Directory path to create
# Returns: Exit code from remote command
ssh_create_dir() {
    local remote_dir="$1"
    
    if [ -z "${REMOTE_HOST}" ] || [ -z "${REMOTE_USER}" ]; then
        log_error "Remote host or user not defined"
        return 1
    fi
    
    log_info "Creating directory on ${REMOTE_HOST}: $remote_dir"
    
    # First check if the directory already exists
    ssh_execute "[ -d \"$remote_dir\" ]"
    if [ $? -eq 0 ]; then
        log_success "Directory already exists: $remote_dir"
        return 0
    fi
    
    # Try to create with sudo to handle permission issues
    ssh_execute_sudo "mkdir -p \"$remote_dir\""
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        # Also ensure the remote user has write permissions to this directory
        ssh_execute_sudo "chown ${REMOTE_USER}:${REMOTE_USER} \"$remote_dir\""
        log_success "Directory created: $remote_dir"
    else
        log_error "Failed to create directory: $remote_dir"
    fi
    
    return $exit_code
}

# Function: ssh_check_mount
# Description: Check if a mount point is mounted on remote host
# Args: $1 - Mount point to check
# Returns: 0 if mounted, 1 otherwise
ssh_check_mount() {
    local mount_point="$1"
    
    if [ -z "${REMOTE_HOST}" ] || [ -z "${REMOTE_USER}" ]; then
        log_error "Remote host or user not defined"
        return 1
    fi
    
    log_info "Checking if mount point is mounted on ${REMOTE_HOST}: $mount_point"
    ssh "${REMOTE_USER}@${REMOTE_HOST}" "mount | grep -q \"on $mount_point \""
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log_info "Mount point is mounted: $mount_point"
    else
        log_info "Mount point is not mounted: $mount_point"
    fi
    
    return $exit_code
}

# Function: ssh_unmount
# Description: Unmount a mount point on remote host
# Args: $1 - Mount point to unmount
# Returns: Exit code from remote command
ssh_unmount() {
    local mount_point="$1"
    
    if [ -z "${REMOTE_HOST}" ] || [ -z "${REMOTE_USER}" ]; then
        log_error "Remote host or user not defined"
        return 1
    fi
    
    log_info "Unmounting on ${REMOTE_HOST}: $mount_point"
    ssh "${REMOTE_USER}@${REMOTE_HOST}" "sudo umount -f \"$mount_point\" 2>/dev/null || true"
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log_success "Unmounted successfully or was not mounted: $mount_point"
    else
        log_error "Failed to unmount: $mount_point"
    fi
    
    return $exit_code
}

# Function: ssh_get_content_visibility
# Description: Check visibility of content in test directories on remote host
# Args: $1 - Base mount point, $2 - Array of directories to check
# Returns: 0 if all directories have content, 1 if none have content, 2 if partial
ssh_get_content_visibility() {
    local mount_point="$1"
    shift
    local dirs=("$@")
    
    if [ -z "${REMOTE_HOST}" ] || [ -z "${REMOTE_USER}" ]; then
        log_error "Remote host or user not defined"
        return 1
    fi
    
    if [ ${#dirs[@]} -eq 0 ]; then
        log_error "No directories specified for content check"
        return 1
    fi
    
    log_info "Checking content visibility in ${#dirs[@]} directories on ${REMOTE_HOST}"
    
    local all_success=true
    local any_success=false
    local visible_dirs=0
    
    for dir in "${dirs[@]}"; do
        # Check if directory exists
        if ssh "${REMOTE_USER}@${REMOTE_HOST}" "[ -d \"$mount_point/$dir\" ]"; then
            # Count files in directory
            local count=$(ssh "${REMOTE_USER}@${REMOTE_HOST}" "find \"$mount_point/$dir\" -type f 2>/dev/null | wc -l")
            
            if [ "$count" -gt 0 ]; then
                log_success "$dir directory shows $count files"
                visible_dirs=$((visible_dirs + 1))
                any_success=true
            else
                log_error "$dir directory shows no files"
                all_success=false
            fi
        else
            log_warning "$dir directory not found"
            all_success=false
        fi
    done
    
    if $all_success; then
        log_success "All test directories show content"
        return 0
    elif $any_success; then
        log_warning "Partial success: $visible_dirs/${#dirs[@]} directories visible"
        return 2
    else
        log_error "No test directories show content"
        return 1
    fi
}
