#!/bin/bash
# report-core.sh - Core reporting functions
# Implements the minimalist multi-module pattern (max 10 functions per module)

# Ensure we have core utilities
if ! type log_info &> /dev/null; then
    echo "ERROR: utils-core.sh must be sourced before report-core.sh"
    exit 1
fi

# Function: initialize_report
# Description: Initialize the report file with header information
initialize_report() {
    local report_file="${RESULT_DIR}/nfs_test_report.md"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    log_info "Initializing test report"
    
    # Create report directory if it doesn't exist
    mkdir -p "${RESULT_DIR}"
    
    # Create the report header
    cat > "$report_file" << EOF
# NFS Troubleshooting Report

**Generated:** $timestamp

## Environment Information

**Server (babka):**
- Hostname: $(hostname -f)
- OS: $(cat /etc/version 2>/dev/null || echo "TrueNAS Scale")
- Export Path: ${EXPORT_PATH:-/mnt/data-tank/docker}

**Client (pita):**
- Hostname: $(ssh_execute "hostname -f")
- OS: $(ssh_execute "cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2")
- Kernel: $(ssh_execute "uname -r")

## Test Summary

This report summarizes the results of comprehensive NFS and alternative protocol tests 
between TrueNAS Scale (babka) and Ubuntu (pita).

EOF
    
    log_success "Report initialized"
    return 0
}

# Function: add_test_summary
# Description: Add test summary section to the report
add_test_summary() {
    local report_file="${RESULT_DIR}/nfs_test_report.md"
    
    log_info "Adding test summary to report"
    
    # Count successful tests by category - do not use grep outside result handling logic
    local nfs_success=0
    local mount_success=0
    local bindfs_success=0
    local smb_success=0
    
    # Count partial tests by category
    local nfs_partial=0
    local mount_partial=0
    local bindfs_partial=0
    local smb_partial=0
    
    # Calculate total tests
    local nfs_total=0
    local mount_total=0
    local bindfs_total=0
    local smb_total=0
    
    # Function to safely count occurrences in a file
    count_occurrences() {
        local file=$1
        local pattern=$2
        local count=0
        
        if [ -f "$file" ]; then
            count=$(grep -c "$pattern" "$file" 2>/dev/null || echo 0)
            # Make sure it's a clean number
            count=$(echo "$count" | tr -d -c '0-9')
            # Default to 0 if empty or not a number
            if [ -z "$count" ] || ! [[ "$count" =~ ^[0-9]+$ ]]; then
                count=0
            fi
        fi
        
        echo $count
    }
    
    # Get the counts safely
    if [ -f "${RESULT_DIR}/results.log" ]; then
        nfs_success=$(count_occurrences "${RESULT_DIR}/results.log" "RESULT:NFS:.*:SUCCESS")
        nfs_partial=$(count_occurrences "${RESULT_DIR}/results.log" "RESULT:NFS:.*:PARTIAL")
        nfs_total=$(count_occurrences "${RESULT_DIR}/results.log" "RESULT:NFS:")
    fi
    
    if [ -f "${RESULT_DIR}/mount_results.log" ]; then
        mount_success=$(count_occurrences "${RESULT_DIR}/mount_results.log" "RESULT:MOUNT:.*:SUCCESS")
        mount_partial=$(count_occurrences "${RESULT_DIR}/mount_results.log" "RESULT:MOUNT:.*:PARTIAL")
        mount_total=$(count_occurrences "${RESULT_DIR}/mount_results.log" "RESULT:MOUNT:")
    fi
    
    if [ -f "${RESULT_DIR}/bindfs_results.log" ]; then
        bindfs_success=$(count_occurrences "${RESULT_DIR}/bindfs_results.log" "RESULT:BINDFS:.*:SUCCESS")
        bindfs_partial=$(count_occurrences "${RESULT_DIR}/bindfs_results.log" "RESULT:BINDFS:.*:PARTIAL")
        bindfs_total=$(count_occurrences "${RESULT_DIR}/bindfs_results.log" "RESULT:BINDFS:")
    fi
    
    if [ -f "${RESULT_DIR}/smb_results.log" ]; then
        smb_success=$(count_occurrences "${RESULT_DIR}/smb_results.log" "RESULT:SMB:.*:SUCCESS")
        smb_partial=$(count_occurrences "${RESULT_DIR}/smb_results.log" "RESULT:SMB:.*:PARTIAL")
        smb_total=$(count_occurrences "${RESULT_DIR}/smb_results.log" "RESULT:SMB:")
    fi
    
    # Calculate failed tests
    local nfs_failed=$((nfs_total - nfs_success - nfs_partial))
    local mount_failed=$((mount_total - mount_success - mount_partial))
    local bindfs_failed=$((bindfs_total - bindfs_success - bindfs_partial))
    local smb_failed=$((smb_total - smb_success - smb_partial))
    
    # Add summary to report
    cat >> "$report_file" << EOF
### Quick Summary

| Test Category | Successful | Partial | Failed | Total |
|---------------|------------|---------|--------|-------|
| NFS Server Configs | $nfs_success | $nfs_partial | $nfs_failed | $nfs_total |
| NFS Client Mounts | $mount_success | $mount_partial | $mount_failed | $mount_total |
| Bindfs Solutions | $bindfs_success | $bindfs_partial | $bindfs_failed | $bindfs_total |
| SMB Alternatives | $smb_success | $smb_partial | $smb_failed | $smb_total |

EOF
    
    log_success "Test summary added to report"
    return 0
}

# Function: add_nfs_server_results
# Description: Add NFS server configuration test results to the report
add_nfs_server_results() {
    local report_file="${RESULT_DIR}/nfs_test_report.md"
    
    log_info "Adding NFS server configuration results to report"
    
    # Check if we have any NFS server test results
    if [ ! -f "${RESULT_DIR}/results.log" ] || ! grep -q "RESULT:NFS:" "${RESULT_DIR}/results.log"; then
        log_warning "No NFS server test results found"
        return 0
    fi
    
    # Add section to report
    cat >> "$report_file" << EOF
## NFS Server Configuration Results

The following table shows the results of testing different NFS server configurations:

| Configuration | Result | Notes |
|---------------|--------|-------|
EOF
    
    # Extract and format results
    grep "RESULT:NFS:" "${RESULT_DIR}/results.log" | while read -r line; do
        local config=$(echo "$line" | cut -d: -f3)
        local result=$(echo "$line" | cut -d: -f4)
        local notes=""
        
        case "$result" in
            SUCCESS)
                notes="All test directories visible"
                ;;
            PARTIAL)
                notes="Some test directories visible"
                ;;
            MOUNT_FAILED)
                notes="Client couldn't mount the export"
                ;;
            NO_CONTENT)
                notes="No directory content visible"
                ;;
            ERROR)
                notes="Error updating configuration"
                ;;
            *)
                notes="Unknown result"
                ;;
        esac
        
        echo "| $config | $result | $notes |" >> "$report_file"
    done
    
    echo "" >> "$report_file"
    log_success "NFS server configuration results added to report"
    return 0
}

# Function: add_nfs_client_results
# Description: Add NFS client mount test results to the report
add_nfs_client_results() {
    local report_file="${RESULT_DIR}/nfs_test_report.md"
    
    log_info "Adding NFS client mount results to report"
    
    # Check if we have any NFS client mount test results
    if [ ! -f "${RESULT_DIR}/mount_results.log" ] || ! grep -q "RESULT:MOUNT:" "${RESULT_DIR}/mount_results.log"; then
        log_warning "No NFS client mount test results found"
        return 0
    fi
    
    # Add section to report
    cat >> "$report_file" << EOF
## NFS Client Mount Results

The following table shows the results of testing different NFS client mount options:

| Configuration | Result | Notes |
|---------------|--------|-------|
EOF
    
    # Extract and format results
    grep "RESULT:MOUNT:" "${RESULT_DIR}/mount_results.log" | while read -r line; do
        local config=$(echo "$line" | cut -d: -f3)
        local result=$(echo "$line" | cut -d: -f4)
        local notes=""
        
        case "$result" in
            SUCCESS)
                notes="All test directories visible"
                ;;
            PARTIAL)
                notes="Some test directories visible"
                ;;
            FAILED)
                notes="Mount command failed"
                ;;
            NO_CONTENT)
                notes="No directory content visible"
                ;;
            *)
                notes="Unknown result"
                ;;
        esac
        
        echo "| $config | $result | $notes |" >> "$report_file"
    done
    
    echo "" >> "$report_file"
    log_success "NFS client mount results added to report"
    return 0
}

# Function: add_bindfs_results
# Description: Add bindfs solution test results to the report
add_bindfs_results() {
    local report_file="${RESULT_DIR}/nfs_test_report.md"
    
    log_info "Adding bindfs solution results to report"
    
    # Check if we have any bindfs test results
    if [ ! -f "${RESULT_DIR}/bindfs_results.log" ] || ! grep -q "RESULT:BINDFS:" "${RESULT_DIR}/bindfs_results.log"; then
        log_warning "No bindfs solution test results found"
        return 0
    fi
    
    # Add section to report
    cat >> "$report_file" << EOF
## Bindfs Solution Results

The following table shows the results of testing bindfs as an alternative solution:

| Configuration | Result | Notes |
|---------------|--------|-------|
EOF
    
    # Extract and format results
    grep "RESULT:BINDFS:" "${RESULT_DIR}/bindfs_results.log" | while read -r line; do
        local config=$(echo "$line" | cut -d: -f3)
        local result=$(echo "$line" | cut -d: -f4)
        local notes=""
        
        case "$result" in
            SUCCESS)
                notes="All test directories visible"
                ;;
            PARTIAL)
                notes="Some test directories visible"
                ;;
            NFS_MOUNT_FAILED)
                notes="Initial NFS mount failed"
                ;;
            BINDFS_MOUNT_FAILED)
                notes="Bindfs mount command failed"
                ;;
            NO_CONTENT)
                notes="No directory content visible"
                ;;
            SYSTEMD_UNITS_CREATED)
                notes="Generated systemd mount units"
                ;;
            *)
                notes="Unknown result"
                ;;
        esac
        
        echo "| $config | $result | $notes |" >> "$report_file"
    done
    
    echo "" >> "$report_file"
    log_success "Bindfs solution results added to report"
    return 0
}

# Function: add_smb_results
# Description: Add SMB alternative test results to the report
add_smb_results() {
    local report_file="${RESULT_DIR}/nfs_test_report.md"
    
    log_info "Adding SMB alternative results to report"
    
    # Check if we have any SMB test results
    if [ ! -f "${RESULT_DIR}/smb_results.log" ] || ! grep -q "RESULT:SMB:" "${RESULT_DIR}/smb_results.log"; then
        log_warning "No SMB alternative test results found"
        return 0
    fi
    
    # Add section to report
    cat >> "$report_file" << EOF
## SMB Alternative Results

The following table shows the results of testing SMB/CIFS as an alternative protocol:

| Configuration | Result | Notes |
|---------------|--------|-------|
EOF
    
    # Extract and format results
    grep "RESULT:SMB:" "${RESULT_DIR}/smb_results.log" | while read -r line; do
        local config=$(echo "$line" | cut -d: -f3)
        local result=$(echo "$line" | cut -d: -f4)
        local notes=""
        
        case "$result" in
            SUCCESS)
                notes="All test directories visible"
                ;;
            PARTIAL)
                notes="Some test directories visible"
                ;;
            MOUNT_FAILED)
                notes="SMB mount command failed"
                ;;
            NO_CONTENT)
                notes="No directory content visible"
                ;;
            SYSTEMD_UNIT_CREATED)
                notes="Generated systemd mount unit"
                ;;
            *)
                notes="Unknown result"
                ;;
        esac
        
        echo "| $config | $result | $notes |" >> "$report_file"
    done
    
    echo "" >> "$report_file"
    log_success "SMB alternative results added to report"
    return 0
}

# Function: add_export_configs
# Description: Add actual NFS export configurations from exportfs
add_export_configs() {
    local report_file="${RESULT_DIR}/nfs_test_report.md"
    
    log_info "Adding detailed NFS export configurations to report"
    
    # Check if we have any export configs
    if [ ! -f "${RESULT_DIR}/export_configs.log" ] || ! grep -q "EXPORT_CONFIG:" "${RESULT_DIR}/export_configs.log"; then
        log_warning "No NFS export configuration details found"
        return 0
    fi
    
    # Add section to report
    cat >> "$report_file" << EOF
## Detailed NFS Export Configurations

This section shows the actual NFS export configurations from \`exportfs -v\` for each test:

| Export Path | Export Options | Test Result |
|-------------|----------------|-------------|
EOF
    
    # Extract and format each export config
    grep "EXPORT_CONFIG:" "${RESULT_DIR}/export_configs.log" | while read -r line; do
        local export_path=$(echo "$line" | cut -d: -f2)
        local export_config=$(echo "$line" | cut -d: -f3-)
        
        # Try to find the matching test result
        local test_result="Unknown"
        if [ -f "${RESULT_DIR}/results.log" ]; then
            local result_line=$(grep -i "RESULT:NFS.*SUCCESS\|RESULT:NFS.*PARTIAL\|RESULT:NFS.*FAILED" "${RESULT_DIR}/results.log" | grep -i "$export_path" | head -1)
            if [ -n "$result_line" ]; then
                test_result=$(echo "$result_line" | cut -d: -f4)
            fi
        fi
        
        # Format the export options by replacing spaces with <br> for better readability
        local formatted_config=$(echo "$export_config" | sed 's/ /\\<br\\>/g')
        
        echo "| $export_path | $formatted_config | $test_result |" >> "$report_file"
    done
    
    # Add correlation with NFS API settings
    cat >> "$report_file" << EOF

### Correlation with TrueNAS API Settings

This table helps understand how TrueNAS API settings translate to NFS export options:

| TrueNAS API Setting | NFS Export Option | Effect |
|---------------------|------------------|--------|
| maproot_user=null, maproot_group=null, mapall_user=null, mapall_group=null | no_root_squash, no_all_squash | No ID mapping |
| maproot_user="root", maproot_group="wheel" | no_root_squash | Root can access files as root |
| mapall_user="root", mapall_group="wheel" | no_root_squash, all_squash, anonuid=0, anongid=0 | All users mapped to root |
| mapall_user="username", mapall_group="groupname" | root_squash, all_squash, anonuid=X, anongid=Y | All users mapped to specific user/group |

These correlations help explain why certain configurations work better than others for access to container directories.
EOF
    
    log_success "NFS export configurations added to report"
    return 0
}


# Function: add_recommendations
# Description: Add recommendations section to the report based on test results
add_recommendations() {
    local report_file="${RESULT_DIR}/nfs_test_report.md"
    
    log_info "Adding recommendations to report"
    
    # Add section header
    cat >> "$report_file" << EOF
## Recommendations

Based on the test results, here are the recommended approaches for connecting babka to pita:

EOF
    
    # Check for successful bindfs solutions
    if grep -q "RESULT:BINDFS:.*:SUCCESS" "${RESULT_DIR}/bindfs_results.log" 2>/dev/null; then
        # Bindfs is the preferred solution if it works
        cat >> "$report_file" << EOF
### Primary Recommendation: Bindfs

The most reliable solution appears to be using bindfs on top of an NFS mount:

1. Mount the NFS share to a temporary location
2. Use bindfs to create a second mount with corrected permissions

#### Implementation:

\`\`\`bash
# Mount NFS share to temporary location
sudo mount -t nfs babka.7homas.com:/mnt/data-tank/docker /mnt/nfs-temp

# Create bindfs mount with correct permissions
sudo bindfs --force-user=${REMOTE_USER} --force-group=${REMOTE_USER} \\
  --create-for-user=root --create-for-group=root \\
  --chown-ignore --chmod-ignore \\
  /mnt/nfs-temp /mnt/docker
\`\`\`

A systemd unit file for this configuration has been generated in the results directory.
EOF
    
    # Check for successful SMB solutions if no bindfs success
    elif grep -q "RESULT:SMB:.*:SUCCESS" "${RESULT_DIR}/smb_results.log" 2>/dev/null; then
        # SMB is the secondary recommendation
        cat >> "$report_file" << EOF
### Primary Recommendation: SMB/CIFS

The most reliable solution appears to be using SMB/CIFS instead of NFS:

1. Use SMB protocol for mounting the share
2. Set appropriate UID/GID and file mode options

#### Implementation:

\`\`\`bash
# Create credentials file
echo "username=${REMOTE_USER}" > ~/.smbcredentials
echo "password=YOUR_PASSWORD_HERE" >> ~/.smbcredentials
chmod 600 ~/.smbcredentials

# Mount SMB share
sudo mount -t cifs -o rw,uid=$(ssh_execute "id -u"),gid=$(ssh_execute "id -g"),file_mode=0755,dir_mode=0755,credentials=~${REMOTE_USER}/.smbcredentials //babka.7homas.com/docker /mnt/docker
\`\`\`

A systemd unit file for this configuration has been generated in the results directory.
EOF
    
    # Check for successful NFS mounts if no bindfs or SMB success
    elif grep -q "RESULT:MOUNT:.*:SUCCESS" "${RESULT_DIR}/mount_results.log" 2>/dev/null; then
        # Direct NFS mount is the tertiary recommendation
        # Get the most successful NFS mount option
        local best_mount=$(grep "RESULT:MOUNT:.*:SUCCESS" "${RESULT_DIR}/mount_results.log" | head -1)
        local best_config=$(echo "$best_mount" | cut -d: -f3)
        
        cat >> "$report_file" << EOF
### Primary Recommendation: Direct NFS Mount

The most reliable solution appears to be a direct NFS mount with specific options:

#### Implementation:

\`\`\`bash
# Mount NFS share with optimized options
sudo mount -t nfs -o rw,hard,noac,actimeo=0 babka.7homas.com:/mnt/data-tank/docker /mnt/docker
\`\`\`

This configuration ($best_config) showed the best results in testing.
EOF
    
    # If nothing works fully but there are partial successes
    elif grep -q "RESULT:.*:PARTIAL" "${RESULT_DIR}"/*_results.log 2>/dev/null; then
        cat >> "$report_file" << EOF
### Recommendation: Further Investigation

No fully successful solution was found, but some configurations showed partial success.
Consider implementing one of the partially successful approaches and testing specific
directories individually.

The most promising approach based on partial results is:
EOF
        
        # Find the most promising partial result
        if grep -q "RESULT:BINDFS:.*:PARTIAL" "${RESULT_DIR}/bindfs_results.log" 2>/dev/null; then
            cat >> "$report_file" << EOF
- Bindfs solution with troubleshooting for specific directories
EOF
        elif grep -q "RESULT:SMB:.*:PARTIAL" "${RESULT_DIR}/smb_results.log" 2>/dev/null; then
            cat >> "$report_file" << EOF
- SMB/CIFS mount with troubleshooting for specific directories
EOF
        else
            cat >> "$report_file" << EOF
- Direct NFS mount with troubleshooting for specific directories
EOF
        fi
    
    # If nothing works at all
    else
        cat >> "$report_file" << EOF
### Recommendation: Alternative Approach

No successful mounting solution was found. Consider the following alternatives:

1. **Individual Directory Mounts**: Mount specific directories individually rather than the parent directory
2. **Container Migration**: Move containers from babka to pita instead of trying to share configurations
3. **Configuration Sync**: Use rsync or similar tools to synchronize configurations rather than mounting
EOF
    fi
    
    # Add secondary recommendations section
    cat >> "$report_file" << EOF

### Additional Recommendations

1. **Systemd Mount Units**: Use systemd mount units to ensure proper mount ordering and dependency handling
2. **Regular Testing**: Periodically test the mount to ensure it remains stable
3. **Monitoring**: Add monitoring for the mount points to detect any issues quickly
EOF
    
    log_success "Recommendations added to report"
    return 0
}

# Function: generate_final_report
# Description: Generate the complete report with all sections
generate_final_report() {
    log_header "Generating final NFS test report"
    
    # Initialize the report
    initialize_report
    
    # Add all sections
    add_test_summary
    add_nfs_server_results
    add_export_configs  # Add the detailed export configurations
    add_nfs_client_results
    add_bindfs_results
    add_smb_results
    add_recommendations
    
    log_success "Final report generated: ${RESULT_DIR}/nfs_test_report.md"
    return 0
}

# Execute the main function if this script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    generate_final_report
fi
