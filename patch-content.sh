#!/bin/bash
# patch-content.sh - Patches for content checking functions in original scripts
# Implements the minimalist multi-module pattern (max 10 functions per module)

# Ensure we have core utilities
if ! type log_info &> /dev/null; then
    echo "ERROR: utils-core.sh must be sourced before patch-content.sh"
    exit 1
fi

# Function: patch_find_commands
# Description: Patch find commands in a script to run via SSH
patch_find_commands() {
    local script="$1"
    
    if [ ! -f "$script" ]; then
        log_error "Script file not found: $script"
        return 1
    fi
    
    log_info "Patching find commands in $script"
    
    # Patch find commands for content checking
    sed -i 's/find "${TEMP_MOUNT}/ssh "${REMOTE_USER}@${REMOTE_HOST}" "find ${TEMP_MOUNT}/g' "$script"
    sed -i 's/find "$test_mount/ssh "${REMOTE_USER}@${REMOTE_HOST}" "find $test_mount/g' "$script"
    
    # Fix double quotes at the end of commands
    sed -i 's/"find \([^"]*\)$/"find \1"/g' "$script"
    
    log_success "Patched find commands in $script"
    return 0
}

# Function: patch_ls_commands
# Description: Patch ls commands in a script to run via SSH
patch_ls_commands() {
    local script="$1"
    
    if [ ! -f "$script" ]; then
        log_error "Script file not found: $script"
        return 1
    fi
    
    log_info "Patching ls commands in $script"
    
    # Patch ls commands for directory listing
    sed -i 's/ls -la "${TEMP_MOUNT}/ssh "${REMOTE_USER}@${REMOTE_HOST}" "ls -la ${TEMP_MOUNT}/g' "$script"
    sed -i 's/ls -la "$test_mount/ssh "${REMOTE_USER}@${REMOTE_HOST}" "ls -la $test_mount/g' "$script"
    
    # Fix double quotes at the end of commands
    sed -i 's/"ls -la \([^"]*\)$/"ls -la \1"/g' "$script"
    
    log_success "Patched ls commands in $script"
    return 0
}

# Function: patch_grep_mount_commands
# Description: Patch grep commands that check mount status
patch_grep_mount_commands() {
    local script="$1"
    
    if [ ! -f "$script" ]; then
        log_error "Script file not found: $script"
        return 1
    fi
    
    log_info "Patching grep mount commands in $script"
    
    # Patch grep commands that check mount status
    sed -i 's/mount | grep /ssh "${REMOTE_USER}@${REMOTE_HOST}" "mount | grep /g' "$script"
    sed -i 's/mount | grep -q /ssh "${REMOTE_USER}@${REMOTE_HOST}" "mount | grep -q /g' "$script"
    
    # Fix double quotes at the end of commands
    sed -i 's/"mount | grep \([^"]*\)$/"mount | grep \1"/g' "$script"
    sed -i 's/"mount | grep -q \([^"]*\)$/"mount | grep -q \1"/g' "$script"
    
    log_success "Patched grep mount commands in $script"
    return 0
}

# Function: patch_file_check_commands
# Description: Patch file/directory existence check commands
patch_file_check_commands() {
    local script="$1"
    
    if [ ! -f "$script" ]; then
        log_error "Script file not found: $script"
        return 1
    fi
    
    log_info "Patching file check commands in $script"
    
    # Patch directory existence check commands
    sed -i 's/\[ -d "${TEMP_MOUNT}/ssh "${REMOTE_USER}@${REMOTE_HOST}" "[ -d ${TEMP_MOUNT}/g' "$script"
    sed -i 's/\[ -d "$test_mount/ssh "${REMOTE_USER}@${REMOTE_HOST}" "[ -d $test_mount/g' "$script"
    
    # Patch file existence check commands
    sed -i 's/\[ -f "${TEMP_MOUNT}/ssh "${REMOTE_USER}@${REMOTE_HOST}" "[ -f ${TEMP_MOUNT}/g' "$script"
    sed -i 's/\[ -f "$test_mount/ssh "${REMOTE_USER}@${REMOTE_HOST}" "[ -f $test_mount/g' "$script"
    
    # Fix double quotes at the end of commands
    sed -i 's/"[ -d \([^"]*\)$/"[ -d \1"/g' "$script"
    sed -i 's/"[ -f \([^"]*\)$/"[ -f \1"/g' "$script"
    
    log_success "Patched file check commands in $script"
    return 0
}

# Function: patch_check_content_function
# Description: Patch the check_content function specifically
patch_check_content_function() {
    local script="$1"
    
    if [ ! -f "$script" ]; then
        log_error "Script file not found: $script"
        return 1
    fi
    
    log_info "Patching check_content function in $script"
    
    # Find the start of the check_content function
    local start_line=$(grep -n "^check_content()" "$script" | cut -d':' -f1)
    
    if [ -z "$start_line" ]; then
        log_warning "check_content function not found in $script"
        return 0
    fi
    
    # Create a modified version of the function that works remotely
    local new_function='check_content() {
    log "Checking content visibility in mount..."
    
    # Use ssh to run this on the remote host
    local visibility=$(ssh "${REMOTE_USER}@${REMOTE_HOST}" "bash -c '\''
        all_success=true
        total_files=0
        visible_dirs=0
        
        for dir in '"${TEST_DIRS[*]}"'; do
            if [ -d \"${TEMP_MOUNT}/${dir}\" ]; then
                count=$(find \"${TEMP_MOUNT}/${dir}\" -type f 2>/dev/null | wc -l)
                total_files=$((total_files + count))
                
                if [ \"$count\" -gt 0 ]; then
                    echo "SUCCESS: ${dir} directory shows $count files"
                    visible_dirs=$((visible_dirs + 1))
                else
                    echo "ERROR: ${dir} directory shows no files"
                    all_success=false
                fi
            else
                echo "WARNING: ${dir} directory not found"
                all_success=false
            fi
        done
        
        if $all_success; then
            exit 0
        elif [ \"$visible_dirs\" -gt 0 ]; then
            exit 2
        else
            exit 1
        fi
    '\'')"
    
    # Get return code from remote command
    local check_result=$?
    
    # Log the output
    echo "$visibility" | while read line; do
        if [[ "$line" == SUCCESS* ]]; then
            success "${line#SUCCESS: }"
        elif [[ "$line" == ERROR* ]]; then
            error "${line#ERROR: }"
        elif [[ "$line" == WARNING* ]]; then
            warning "${line#WARNING: }"
        fi
    done
    
    if [ $check_result -eq 0 ]; then
        success "All test directories show content"
    elif [ $check_result -eq 2 ]; then
        warning "Partial success: Some directories show content"
    else
        error "No test directories show content"
    fi
    
    return $check_result
}'
    
    # Find the end of the function
    local next_function_line=$(tail -n +$((start_line+1)) "$script" | grep -n "^[a-zA-Z0-9_]\+()" | head -1 | cut -d':' -f1)
    
    if [ -z "$next_function_line" ]; then
        # If we can't find the next function, assume the function goes to the end of the file
        sed -i "${start_line},$ s/^check_content().*/${new_function}/" "$script"
    else
        # Replace the function with our modified version
        local end_line=$((start_line + next_function_line - 1))
        sed -i "${start_line},${end_line} s/^check_content().*/${new_function}/" "$script"
    fi
    
    log_success "Patched check_content function in $script"
    return 0
}

# Function: apply_content_patches
# Description: Apply all content checking patches to scripts
apply_content_patches() {
    local patched_dir="${PATCHED_DIR:-./patched}"
    
    for script in "$patched_dir"/*.sh; do
        if [ -f "$script" ]; then
            patch_find_commands "$script"
            patch_ls_commands "$script"
            patch_grep_mount_commands "$script"
            patch_file_check_commands "$script"
            patch_check_content_function "$script"
        fi
    done
    
    log_success "All content checking commands patched"
    return 0
}

# Execute the main function if this script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    apply_content_patches
fi
