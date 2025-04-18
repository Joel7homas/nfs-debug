#!/bin/bash
# alt-smb.sh - Functions for testing SMB/CIFS alternatives
# Implements the minimalist multi-module pattern (max 10 functions per module)
# Updated to fix credentials path issues and UID/GID handling

# Ensure we have core utilities
if ! type log_info &> /dev/null; then
    echo "ERROR: utils-core.sh must be sourced before alt-smb.sh"
    exit 1
fi

# Ensure we have SSH utilities
if ! type ssh_execute &> /dev/null; then
    echo "ERROR: utils-ssh.sh must be sourced before alt-smb.sh"
    exit 1
fi

# Function: check_cifs_utils_installed
# Description: Check if CIFS utils are installed on remote host
check_cifs_utils_installed() {
    log_info "Checking if CIFS utils are installed on remote host"
    
    ssh_execute "command -v mount.cifs"
    if [ $? -ne 0 ]; then
        log_warning "CIFS utils not installed on remote host"
        
        # Try to install cifs-utils
        log_info "Attempting to install cifs-utils on remote host"
        ssh_execute_sudo "apt-get update && apt-get install -y cifs-utils"
        
        # Check if installation was successful
        ssh_execute "command -v mount.cifs"
        if [ $? -ne 0 ]; then
            log_error "Failed to install cifs-utils on remote host"
            return 1
        fi
        
        log_success "cifs-utils installed on remote host"
    else
        log_success "cifs-utils already installed on remote host"
    fi
    
    return 0
}

# Function: prepare_smb_mount_point
# Description: Prepare mount point for SMB testing
prepare_smb_mount_point() {
    local mount_point="${REMOTE_SMB_MOUNT:-/mnt/smb-test}"
    
    log_info "Preparing SMB mount point: $mount_point"
    
    # Unmount if already mounted
    ssh_unmount "$mount_point"
    
    # Create mount point
    ssh_create_dir "$mount_point"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create SMB mount point"
        return 1
    fi
    
    log_success "SMB mount point prepared"
    return 0
}

# Function: create_smb_share
# Description: Create SMB share on TrueNAS for testing
create_smb_share() {
    local export_path="${EXPORT_PATH:-/mnt/data-tank/docker}"
    local share_name="${SMB_SHARE_NAME:-docker}"
    
    log_info "Creating SMB share for testing"
    
    # Check if share already exists
    local share_exists=$(midclt call "sharing.smb.query" "[[\"path\", \"=\", \"$export_path\"]]")
    
    if [ "$share_exists" != "[]" ]; then
        log_info "SMB share already exists for $export_path"
        return 0
    fi
    
    # Create the SMB share with current TrueNAS API format
    local share_config="{
        \"path\": \"$export_path\",
        \"name\": \"$share_name\",
        \"comment\": \"Docker configuration share for testing\",
        \"purpose\": \"NO_PRESET\",
        \"path_suffix\": \"\",
        \"home\": false,
        \"ro\": false,
        \"browsable\": true,
        \"auxsmbconf\": \"create mask=0755\\ndirectory mask=0755\",
        \"aapl_name_mangling\": false,
        \"streams\": false,
        \"durablehandle\": true,
        \"fsrvp\": false
    }"
    
    midclt call "sharing.smb.create" "$share_config" > /dev/null
    if [ $? -ne 0 ]; then
        log_error "Failed to create SMB share"
        return 1
    fi
    
    # Restart SMB service to apply changes
    midclt call "service.restart" "cifs"
    
    log_success "SMB share created"
    return 0
}


# Function: create_smb_credentials_quiet
# Description: Create SMB credentials file on remote host without logs
# Args: $1 - Username, $2 - Password
# Returns: Path to credentials file
create_smb_credentials_quiet() {
    local username="$1"
    local password="$2"
    local remote_user="${REMOTE_USER:-joel}"
    
    # Create absolute path for credentials file
    local creds_file="/home/${remote_user}/.smbcreds-test"
    
    # Create the credentials file with proper permissions
    ssh_execute "echo \"username=${username}\" > \"$creds_file\" && echo \"password=${password}\" >> \"$creds_file\" && chmod 600 \"$creds_file\" && echo \"$creds_file\""
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    return 0
}

# Function: get_remote_uid_gid_quiet
# Description: Get UID and GID of remote user without logs
# Returns: String in format "uid=X,gid=Y"
get_remote_uid_gid_quiet() {
    # Get UID and GID directly without intermediate variables
    local uid_gid=$(ssh_execute "echo uid=\$(id -u),gid=\$(id -g)")
    
    # Return the uid_gid string directly
    echo "$uid_gid"
    return 0
}

# Function: enable_guest_access
# Description: Enable guest access on SMB share
enable_guest_access() {
    local export_path="${EXPORT_PATH:-/mnt/data-tank/docker}"
    local share_name="${SMB_SHARE_NAME:-docker}"
    
    log_info "Enabling guest access on SMB share"
    
    # Check if share exists
    local share_data=$(midclt call "sharing.smb.query" "[[\"path\", \"=\", \"$export_path\"]]")
    
    if [ "$share_data" == "[]" ]; then
        log_error "SMB share not found for $export_path"
        return 1
    fi
    
    # Get the share ID
    local share_id=$(echo "$share_data" | jq -r '.[0].id')
    
    # Try simplest update with just guestok
    log_info "Setting guestok=true on SMB share"
    midclt call "sharing.smb.update" "$share_id" '{"guestok": true}'
    
    if [ $? -ne 0 ]; then
        log_error "Failed to enable guest access on SMB share"
        return 1
    fi
    
    # Restart SMB service to apply changes
    midclt call "service.restart" "cifs"
    
    log_success "Guest access enabled on SMB share"
    return 0
}

# Function: test_smb_mount
# Description: Test SMB mount with specific options
# Args: $1 - Description, $2 - Mount options
test_smb_mount() {
    local description="$1"
    local mount_options="$2"
    local mount_point="${REMOTE_SMB_MOUNT:-/mnt/smb-test}"
    local server_host=$(hostname -f)
    local share_name="${SMB_SHARE_NAME:-docker}"
    
    log_header "Testing SMB mount: $description"
    
    # Check if CIFS utils are installed
    check_cifs_utils_installed
    if [ $? -ne 0 ]; then
        log_error "Skipping SMB test: cifs-utils not available"
        echo "RESULT:SMB:$description:NO_CIFS_UTILS" >> "${RESULT_DIR}/smb_results.log"
        return 1
    fi
    
    # Create SMB share if needed
    create_smb_share
    if [ $? -ne 0 ]; then
        log_error "Skipping SMB test: Failed to create SMB share"
        echo "RESULT:SMB:$description:SHARE_CREATION_FAILED" >> "${RESULT_DIR}/smb_results.log"
        return 1
    fi
    
    # Try to enable guest access
    enable_guest_access
    
    # Prepare mount point
    prepare_smb_mount_point
    
    # Get server IP address (use IP instead of hostname to avoid DNS issues)
    local server_ip=$(hostname -I | awk '{print $1}')
    
    # Try different authentication methods
    
    # 1. First try guest access
    log_info "Attempting mount with guest access"
    local guest_cmd="mount -t cifs -o ${mount_options},guest //${server_ip}/${share_name} ${mount_point}"
    log_info "Guest mount command: $guest_cmd"
    
    ssh_execute_sudo "$guest_cmd"
    local guest_result=$?
    
    if [ $guest_result -eq 0 ]; then
        log_success "Guest mount successful"
        
        # Check content visibility
        ssh_get_content_visibility "$mount_point" "${TEST_DIRS[@]}"
        local content_result=$?
        
        # Unmount
        ssh_unmount "$mount_point"
        
        # Record result
        if [ $content_result -eq 0 ]; then
            log_success "SMB guest mount successful: $description"
            echo "RESULT:SMB:$description:SUCCESS" >> "${RESULT_DIR}/smb_results.log"
        elif [ $content_result -eq 2 ]; then
            log_warning "SMB guest mount partially successful: $description"
            echo "RESULT:SMB:$description:PARTIAL" >> "${RESULT_DIR}/smb_results.log"
        else
            log_error "SMB guest mount failed: $description"
            echo "RESULT:SMB:$description:NO_CONTENT" >> "${RESULT_DIR}/smb_results.log"
        fi
        
        return $content_result
    else
        log_warning "Guest mount failed, will try with credentials"
    fi
    
    # 2. Try with direct username/password
    local username="${SMB_USERNAME:-${REMOTE_USER}}"
    local password="${SMB_PASSWORD:-password}"
    
    log_info "Trying mount with direct username/password"
    local direct_cmd="mount -t cifs -o ${mount_options},username=${username},password=${password},vers=3.0 //${server_ip}/${share_name} ${mount_point}"
    log_info "Direct auth mount command: mount -t cifs -o ${mount_options},username=*****,password=*****,vers=3.0 //${server_ip}/${share_name} ${mount_point}"
    
    ssh_execute_sudo "$direct_cmd"
    local direct_result=$?
    
    if [ $direct_result -eq 0 ]; then
        log_success "Direct authentication mount successful"
        
        # Check content visibility
        ssh_get_content_visibility "$mount_point" "${TEST_DIRS[@]}"
        local content_result=$?
        
        # Unmount
        ssh_unmount "$mount_point"
        
        # Record result
        if [ $content_result -eq 0 ]; then
            log_success "SMB direct auth mount successful: $description"
            echo "RESULT:SMB:$description:SUCCESS" >> "${RESULT_DIR}/smb_results.log"
        elif [ $content_result -eq 2 ]; then
            log_warning "SMB direct auth mount partially successful: $description"
            echo "RESULT:SMB:$description:PARTIAL" >> "${RESULT_DIR}/smb_results.log"
        else
            log_error "SMB direct auth mount failed: $description"
            echo "RESULT:SMB:$description:NO_CONTENT" >> "${RESULT_DIR}/smb_results.log"
        fi
        
        return $content_result
    else 
        log_warning "Direct authentication mount failed, will try with credentials file"
    fi
    
    # 3. Try with credentials file
    local creds_file
    creds_file=$(create_smb_credentials_quiet "$username" "$password")
    
    # Trim whitespace from creds_file
    creds_file=$(echo "$creds_file" | tr -d '[:space:]')
    
    if [ -z "$creds_file" ]; then
        log_error "Failed to create credentials file"
        echo "RESULT:SMB:$description:CREDENTIALS_FAILED" >> "${RESULT_DIR}/smb_results.log"
        return 1
    fi
    
    log_info "Created credentials file at: $creds_file"
    
    # Create and log the complete mount command - single line with no newlines
    local mount_cmd="mount -t cifs -o ${mount_options},credentials=${creds_file},vers=3.0 //${server_ip}/${share_name} ${mount_point}"
    log_info "Mount command: $mount_cmd"
    
    # Execute the mount command
    ssh_execute_sudo "$mount_cmd"
    local mount_result=$?
    
    if [ $mount_result -eq 0 ]; then
        log_success "Credentials file mount successful"
        
        # Check content visibility
        ssh_get_content_visibility "$mount_point" "${TEST_DIRS[@]}"
        local content_result=$?
        
        # Unmount
        ssh_unmount "$mount_point"
        
        # Clean up credentials file
        ssh_execute "rm -f \"${creds_file}\""
        
        # Record result
        if [ $content_result -eq 0 ]; then
            log_success "SMB credentials mount successful: $description"
            echo "RESULT:SMB:$description:SUCCESS" >> "${RESULT_DIR}/smb_results.log"
        elif [ $content_result -eq 2 ]; then
            log_warning "SMB credentials mount partially successful: $description"
            echo "RESULT:SMB:$description:PARTIAL" >> "${RESULT_DIR}/smb_results.log"
        else
            log_error "SMB credentials mount failed: $description"
            echo "RESULT:SMB:$description:NO_CONTENT" >> "${RESULT_DIR}/smb_results.log"
        fi
        
        return $content_result
    fi
    
    # All methods failed
    log_error "All SMB mount attempts failed"
    echo "RESULT:SMB:$description:MOUNT_FAILED" >> "${RESULT_DIR}/smb_results.log"
    
    # Clean up credentials file
    if [ -n "$creds_file" ]; then
        ssh_execute "rm -f \"${creds_file}\""
    fi
    
    return 1
}

# Function: test_smb_basic
# Description: Test basic SMB mount
test_smb_basic() {
    test_smb_mount "Basic SMB" "rw"
    return $?
}

# Function: test_smb_with_file_mode
# Description: Test SMB mount with file mode options
test_smb_with_file_mode() {
    test_smb_mount "SMB with file mode" "rw,file_mode=0755,dir_mode=0755"
    return $?
}

# Function: test_smb_with_uid_gid
# Description: Test SMB mount with specific UID/GID
test_smb_with_uid_gid() {
    test_smb_mount "SMB with UID/GID" "rw"
    return $?
}

# Function: test_smb_with_noperm
# Description: Test SMB mount with noperm option
test_smb_with_noperm() {
    test_smb_mount "SMB with noperm" "rw,noperm"
    return $?
}

# Function: create_smb_systemd_unit
# Description: Create systemd unit file for successful SMB configuration
create_smb_systemd_unit() {
    local description="$1"
    local mount_options="$2"
    local mount_point="${REMOTE_SMB_MOUNT:-/mnt/smb-test}"
    local server_host=$(hostname -f)
    local share_name="${SMB_SHARE_NAME:-docker}"
    local username="${SMB_USERNAME:-${REMOTE_USER}}"
    local remote_user="${REMOTE_USER:-joel}"
    
    log_info "Creating systemd unit file for successful SMB configuration"
    
    # Use absolute paths for credentials
    local creds_path="/home/${remote_user}/.smbcredentials"
    
    # Create SMB mount unit
    local smb_unit="[Unit]
Description=Mount SMB Share from TrueNAS
After=network.target

[Mount]
What=//${server_host}/${share_name}
Where=${mount_point}
Type=cifs
Options=${mount_options},credentials=${creds_path}
TimeoutSec=30

[Install]
WantedBy=multi-user.target"

    # Create credentials file script
    local creds_script="#!/bin/bash
# Create SMB credentials file
echo \"username=${username}\" > ${creds_path}
echo \"password=YOUR_PASSWORD_HERE\" >> ${creds_path}
chmod 600 ${creds_path}
echo \"SMB credentials file created at ${creds_path}\"
echo \"Edit this file and replace YOUR_PASSWORD_HERE with your actual password\"
"

    # Write the files to the results directory
    mkdir -p "${RESULT_DIR}/systemd-units"
    echo "$smb_unit" > "${RESULT_DIR}/systemd-units/smb-mount.mount"
    echo "$creds_script" > "${RESULT_DIR}/systemd-units/create-smb-credentials.sh"
    chmod +x "${RESULT_DIR}/systemd-units/create-smb-credentials.sh"
    
    log_success "Created systemd unit files in ${RESULT_DIR}/systemd-units/"
    echo "RESULT:SMB:$description:SYSTEMD_UNIT_CREATED" >> "${RESULT_DIR}/smb_results.log"
    
    return 0
}

# Function: test_smb_solutions
# Description: Run all SMB solution tests
test_smb_solutions() {
    log_header "Testing SMB alternative solutions"
    
    # Ensure results directory exists
    mkdir -p "${RESULT_DIR}"
    
    # Run all SMB tests
    test_smb_basic
    test_smb_with_file_mode
    test_smb_with_uid_gid
    test_smb_with_noperm
    
    # Create systemd unit file for successful configurations
    if grep -q "RESULT:SMB:.*:SUCCESS" "${RESULT_DIR}/smb_results.log" 2>/dev/null; then
        local success_config=$(grep "RESULT:SMB:.*:SUCCESS" "${RESULT_DIR}/smb_results.log" | head -1)
        local description=$(echo "$success_config" | cut -d: -f3)
        
        # Use the UID/GID solution parameters for the systemd unit
        local uid_gid=$(get_remote_uid_gid_quiet)
        create_smb_systemd_unit "$description" "rw,${uid_gid},file_mode=0755,dir_mode=0755"
    fi
    
    log_success "All SMB solutions tested"
    
    # Generate summary with proper error handling
    local success_count=0
    local partial_count=0
    local failed_count=0
    
    # Safely count results with proper error handling
    if [ -f "${RESULT_DIR}/smb_results.log" ]; then
        # Clean whitespace and handle multiline output
        success_count=$(grep -c "RESULT:SMB:.*:SUCCESS" "${RESULT_DIR}/smb_results.log" 2>/dev/null || echo 0)
        partial_count=$(grep -c "RESULT:SMB:.*:PARTIAL" "${RESULT_DIR}/smb_results.log" 2>/dev/null || echo 0)
        failed_count=$(grep -c "RESULT:SMB:.*:NO_CONTENT\|RESULT:SMB:.*:MOUNT_FAILED" "${RESULT_DIR}/smb_results.log" 2>/dev/null || echo 0)
        
        # Ensure we have clean integers
        success_count=${success_count//[^0-9]/}
        partial_count=${partial_count//[^0-9]/}
        failed_count=${failed_count//[^0-9]/}
        
        # Default to 0 if empty
        success_count=${success_count:-0}
        partial_count=${partial_count:-0}
        failed_count=${failed_count:-0}
    fi
    
    log_info "Summary: $success_count successful, $partial_count partial, $failed_count failed SMB solutions"
    
    # Ensure we're using numeric comparisons
    if [ "$success_count" -gt 0 ]; then
        return 0
    elif [ "$partial_count" -gt 0 ]; then
        return 2
    else
        return 1
    fi
}

# Execute the main function if this script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    test_smb_solutions
fi
