#!/bin/bash
# alt-smb.sh - Functions for testing SMB/CIFS alternatives
# Implements the minimalist multi-module pattern (max 10 functions per module)

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
    
    # Create the SMB share
    local share_config="{
        \"path\": \"$export_path\",
        \"name\": \"$share_name\",
        \"comment\": \"Docker configuration share for testing\",
        \"purpose\": \"NO_PRESET\",
        \"path_suffix\": \"\",
        \"home\": false,
        \"ro\": false,
        \"browsable\": true,
        \"timemachine\": false,
        \"recyclebin\": false,
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
    
    # Prepare mount point
    prepare_smb_mount_point
    
    # Get credentials for mount
    local username="${SMB_USERNAME:-${REMOTE_USER}}"
    local password="${SMB_PASSWORD:-password}"
    
    # Create credentials file on remote host
    ssh_execute "echo \"username=$username\" > ~/.smbcredentials && echo \"password=$password\" >> ~/.smbcredentials && chmod 600 ~/.smbcredentials"
    
    # Mount SMB share
    log_info "Mounting SMB share with options: $mount_options"
    ssh_execute_sudo "mount -t cifs -o $mount_options,credentials=~$username/.smbcredentials //$server_host/$share_name $mount_point"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to mount SMB share"
        echo "RESULT:SMB:$description:MOUNT_FAILED" >> "${RESULT_DIR}/smb_results.log"
        
        # Clean up credentials file
        ssh_execute "rm -f ~/.smbcredentials"
        
        return 1
    fi
    
    # Check content visibility
    ssh_get_content_visibility "$mount_point" "${TEST_DIRS[@]}"
    local content_result=$?
    
    # Record result
    if [ $content_result -eq 0 ]; then
        log_success "SMB mount successful: $description"
        echo "RESULT:SMB:$description:SUCCESS" >> "${RESULT_DIR}/smb_results.log"
    elif [ $content_result -eq 2 ]; then
        log_warning "SMB mount partially successful: $description"
        echo "RESULT:SMB:$description:PARTIAL" >> "${RESULT_DIR}/smb_results.log"
    else
        log_error "SMB mount failed: $description"
        echo "RESULT:SMB:$description:NO_CONTENT" >> "${RESULT_DIR}/smb_results.log"
    fi
    
    # Clean up
    ssh_unmount "$mount_point"
    ssh_execute "rm -f ~/.smbcredentials"
    
    return $content_result
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
    local uid=$(ssh_execute "id -u")
    local gid=$(ssh_execute "id -g")
    test_smb_mount "SMB with UID/GID" "rw,uid=$uid,gid=$gid"
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
    
    log_info "Creating systemd unit file for successful SMB configuration"
    
    # Create SMB mount unit
    local smb_unit="[Unit]
Description=Mount SMB Share from TrueNAS
After=network.target

[Mount]
What=//${server_host}/${share_name}
Where=${mount_point}
Type=cifs
Options=${mount_options},credentials=/home/${username}/.smbcredentials
TimeoutSec=30

[Install]
WantedBy=multi-user.target"

    # Create credentials file script
    local creds_script="#!/bin/bash
# Create SMB credentials file
echo \"username=${username}\" > ~/.smbcredentials
echo \"password=YOUR_PASSWORD_HERE\" >> ~/.smbcredentials
chmod 600 ~/.smbcredentials
echo \"SMB credentials file created at ~/.smbcredentials\"
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
    if grep -q "RESULT:SMB:.*:SUCCESS" "${RESULT_DIR}/smb_results.log"; then
        local success_config=$(grep "RESULT:SMB:.*:SUCCESS" "${RESULT_DIR}/smb_results.log" | head -1)
        local description=$(echo "$success_config" | cut -d: -f3)
        
        # Use the UID/GID solution parameters for the systemd unit
        local uid=$(ssh_execute "id -u")
        local gid=$(ssh_execute "id -g")
        create_smb_systemd_unit "$description" "rw,uid=$uid,gid=$gid,file_mode=0755,dir_mode=0755"
    fi
    
    log_success "All SMB solutions tested"
    
    # Generate summary
    local success_count=$(grep -c "RESULT:SMB:.*:SUCCESS" "${RESULT_DIR}/smb_results.log")
    local partial_count=$(grep -c "RESULT:SMB:.*:PARTIAL" "${RESULT_DIR}/smb_results.log")
    local failed_count=$(grep -c "RESULT:SMB:.*:NO_CONTENT\|RESULT:SMB:.*:MOUNT_FAILED" "${RESULT_DIR}/smb_results.log")
    
    log_info "Summary: $success_count successful, $partial_count partial, $failed_count failed SMB solutions"
    
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
    test_smb_solutions
fi
