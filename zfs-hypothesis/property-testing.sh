#!/bin/bash
# property-testing.sh - Functions for testing ZFS property effects on visibility
# Follows minimalist multi-module pattern (max 10 functions per module)

# Source the core utilities if not already loaded
if ! type log_info &> /dev/null; then
    source ./nested-dataset-test-core.sh
fi

# Function: test_sharenfs_property
# Description: Test effect of sharenfs property on visibility
test_sharenfs_property() {
    log_header "Testing sharenfs property effects"
    
    local parent_dataset="${BASE_DATASET}/${TEST_PARENT}"
    local child_dataset="${parent_dataset}/${TEST_CHILD}"
    local parent_path=$(sudo zfs get -H -o value mountpoint "${parent_dataset}")
    local child_path=$(sudo zfs get -H -o value mountpoint "${child_dataset}")
    
    # Create baseline exports
    cleanup_all_exports
    
    # Test 1: sharenfs=off on both
    log_info "Test 1: sharenfs=off on both datasets"
    set_dataset_property "${parent_dataset}" "sharenfs" "off"

    # Add diagnostic info
    log_info "Checking current NFS exports:"
    sudo midclt call sharing.nfs.query | grep -v password | tee -a "${LOG_FILE}" || true
    log_info "Checking system NFS shares:"
    sudo showmount -e | tee -a "${LOG_FILE}" || true
    set_dataset_property "${child_dataset}" "sharenfs" "off"

    # Add diagnostic info
    log_info "Checking current NFS exports:"
    sudo midclt call sharing.nfs.query | grep -v password | tee -a "${LOG_FILE}" || true
    log_info "Checking system NFS shares:"
    sudo showmount -e | tee -a "${LOG_FILE}" || true
    create_nfs_export "${parent_path}" "sharenfs_off_both"
    
    # Test parent export
    test_nfs_visibility "${parent_path}" "sharenfs_off_both_parent" "parent-file.txt" "child-file.txt"
    
    # Test 2: sharenfs=on for parent, off for child
    log_info "Test 2: sharenfs=on for parent, off for child"
    set_dataset_property "${parent_dataset}" "sharenfs" "on"

    # Add diagnostic info
    log_info "Checking current NFS exports:"
    sudo midclt call sharing.nfs.query | grep -v password | tee -a "${LOG_FILE}" || true
    log_info "Checking system NFS shares:"
    sudo showmount -e | tee -a "${LOG_FILE}" || true
    set_dataset_property "${child_dataset}" "sharenfs" "off"

    # Add diagnostic info
    log_info "Checking current NFS exports:"
    sudo midclt call sharing.nfs.query | grep -v password | tee -a "${LOG_FILE}" || true
    log_info "Checking system NFS shares:"
    sudo showmount -e | tee -a "${LOG_FILE}" || true
    cleanup_all_exports
    
    # The sharenfs=on should create an export automatically
    test_nfs_visibility "${parent_path}" "sharenfs_on_parent_off_child" "parent-file.txt" "child-file.txt"
    
    # Test 3: sharenfs=off for parent, on for child
    log_info "Test 3: sharenfs=off for parent, on for child"
    set_dataset_property "${parent_dataset}" "sharenfs" "off"

    # Add diagnostic info
    log_info "Checking current NFS exports:"
    sudo midclt call sharing.nfs.query | grep -v password | tee -a "${LOG_FILE}" || true
    log_info "Checking system NFS shares:"
    sudo showmount -e | tee -a "${LOG_FILE}" || true
    set_dataset_property "${child_dataset}" "sharenfs" "on"

    # Add diagnostic info
    log_info "Checking current NFS exports:"
    sudo midclt call sharing.nfs.query | grep -v password | tee -a "${LOG_FILE}" || true
    log_info "Checking system NFS shares:"
    sudo showmount -e | tee -a "${LOG_FILE}" || true
    cleanup_all_exports
    
    # The child sharenfs=on should create an export automatically
    test_nfs_visibility "${child_path}" "sharenfs_off_parent_on_child" "child-file.txt"
    
    # Test 4: sharenfs=on for both
    log_info "Test 4: sharenfs=on for both"
    set_dataset_property "${parent_dataset}" "sharenfs" "on"

    # Add diagnostic info
    log_info "Checking current NFS exports:"
    sudo midclt call sharing.nfs.query | grep -v password | tee -a "${LOG_FILE}" || true
    log_info "Checking system NFS shares:"
    sudo showmount -e | tee -a "${LOG_FILE}" || true
    set_dataset_property "${child_dataset}" "sharenfs" "on"

    # Add diagnostic info
    log_info "Checking current NFS exports:"
    sudo midclt call sharing.nfs.query | grep -v password | tee -a "${LOG_FILE}" || true
    log_info "Checking system NFS shares:"
    sudo showmount -e | tee -a "${LOG_FILE}" || true
    cleanup_all_exports
    
    # Both exports should be created automatically
    test_nfs_visibility "${parent_path}" "sharenfs_on_both_parent" "parent-file.txt" "child-file.txt"
    test_nfs_visibility "${child_path}" "sharenfs_on_both_child" "child-file.txt"
    
    # Cleanup
    set_dataset_property "${parent_dataset}" "sharenfs" "off"

    # Add diagnostic info
    log_info "Checking current NFS exports:"
    sudo midclt call sharing.nfs.query | grep -v password | tee -a "${LOG_FILE}" || true
    log_info "Checking system NFS shares:"
    sudo showmount -e | tee -a "${LOG_FILE}" || true
    set_dataset_property "${child_dataset}" "sharenfs" "off"

    # Add diagnostic info
    log_info "Checking current NFS exports:"
    sudo midclt call sharing.nfs.query | grep -v password | tee -a "${LOG_FILE}" || true
    log_info "Checking system NFS shares:"
    sudo showmount -e | tee -a "${LOG_FILE}" || true
    cleanup_all_exports
    
    log_success "sharenfs property testing completed"
    return 0
}

# Function: test_aclinherit_property
# Description: Test effect of aclinherit property on visibility
test_aclinherit_property() {
    log_header "Testing aclinherit property effects"
    
    local parent_dataset="${BASE_DATASET}/${TEST_PARENT}"
    local child_dataset="${parent_dataset}/${TEST_CHILD}"
    local parent_path=$(sudo zfs get -H -o value mountpoint "${parent_dataset}")
    
    # Create baseline exports
    cleanup_all_exports
    create_nfs_export "${parent_path}" "aclinherit_test"
    
    # Test options: restricted, passthrough, passthrough-x, discard
    local aclinherit_options=("restricted" "passthrough" "passthrough-x" "discard")
    
    for option in "${aclinherit_options[@]}"; do
        log_info "Testing aclinherit=${option}"
        
        # Set property on both datasets
        set_dataset_property "${parent_dataset}" "aclinherit" "${option}"
        set_dataset_property "${child_dataset}" "aclinherit" "${option}"
        
        # Test visibility
        test_nfs_visibility "${parent_path}" "aclinherit_${option}" "parent-file.txt" "child-file.txt"
    done
    
    # Cleanup
    cleanup_all_exports
    
    log_success "aclinherit property testing completed"
    return 0
}

# Function: test_acltype_property
# Description: Test effect of acltype property on visibility
test_acltype_property() {
    log_header "Testing acltype property effects"
    
    local parent_dataset="${BASE_DATASET}/${TEST_PARENT}"
    local child_dataset="${parent_dataset}/${TEST_CHILD}"
    local parent_path=$(sudo zfs get -H -o value mountpoint "${parent_dataset}")
    
    # Create baseline exports
    cleanup_all_exports
    create_nfs_export "${parent_path}" "acltype_test"
    
    # Test options: off, nfsv4, posix
    local acltype_options=("off" "nfsv4" "posix")
    
    for option in "${acltype_options[@]}"; do
        log_info "Testing acltype=${option}"
        
        # Set property on both datasets
        set_dataset_property "${parent_dataset}" "acltype" "${option}"
        set_dataset_property "${child_dataset}" "acltype" "${option}"
        
        # Test visibility
        test_nfs_visibility "${parent_path}" "acltype_${option}" "parent-file.txt" "child-file.txt"
    done
    
    # Cleanup
    cleanup_all_exports
    
    log_success "acltype property testing completed"
    return 0
}

# Function: test_nested_dataset_hypothesis
# Description: Test the nested dataset hypothesis
test_nested_dataset_hypothesis() {
    log_header "Testing nested dataset hypothesis"
    
    local parent_dataset="${BASE_DATASET}/${TEST_PARENT}"
    local child_dataset="${parent_dataset}/${TEST_CHILD}"
    local parent_path=$(sudo zfs get -H -o value mountpoint "${parent_dataset}")
    local child_path=$(sudo zfs get -H -o value mountpoint "${child_dataset}")
    
    # Create baseline exports
    cleanup_all_exports
    
    # Test 1: Parent export only
    log_info "Test 1: Parent export only"
    create_nfs_export "${parent_path}" "parent_only"
    create_smb_share "${parent_path}" "parent_only"
    
    # Test NFS visibility
    test_nfs_visibility "${parent_path}" "nested_parent_only_nfs" "parent-file.txt" "child-file.txt"
    
    # Test SMB visibility
    test_smb_visibility "parent_only" "nested_parent_only_smb" "parent-file.txt" "child-file.txt"
    
    # Test 2: Child export only
    log_info "Test 2: Child export only"
    cleanup_all_exports
    create_nfs_export "${child_path}" "child_only"
    create_smb_share "${child_path}" "child_only"
    
    # Test NFS visibility
    test_nfs_visibility "${child_path}" "nested_child_only_nfs" "child-file.txt"
    
    # Test SMB visibility
    test_smb_visibility "child_only" "nested_child_only_smb" "child-file.txt"
    
    # Test 3: Both exports
    log_info "Test 3: Both parent and child exports"
    cleanup_all_exports
    create_nfs_export "${parent_path}" "both_parent"
    create_nfs_export "${child_path}" "both_child"
    create_smb_share "${parent_path}" "both_parent"
    create_smb_share "${child_path}" "both_child"
    
    # Test NFS visibility
    test_nfs_visibility "${parent_path}" "nested_both_parent_nfs" "parent-file.txt" "child-file.txt"
    test_nfs_visibility "${child_path}" "nested_both_child_nfs" "child-file.txt"
    
    # Test SMB visibility
    test_smb_visibility "both_parent" "nested_both_parent_smb" "parent-file.txt" "child-file.txt"
    test_smb_visibility "both_child" "nested_both_child_smb" "child-file.txt"
    
    # Cleanup
    cleanup_all_exports
    
    log_success "Nested dataset hypothesis testing completed"
    return 0
}

# Function: test_regular_dir_vs_datasets
# Description: Test visibility differences between regular directories and nested datasets
test_regular_dir_vs_datasets() {
    log_header "Testing regular directories vs. nested datasets"
    
    local parent_dataset="${BASE_DATASET}/${TEST_PARENT}"
    local parent_path=$(sudo zfs get -H -o value mountpoint "${parent_dataset}")
    
    # Create baseline exports
    cleanup_all_exports
    create_nfs_export "${parent_path}" "parent_with_regular_dirs"
    create_smb_share "${parent_path}" "parent_with_regular_dirs"
    
    # Test parent export - should show all regular directories and all dataset directories
    test_nfs_visibility "${parent_path}" "regular_dir_vs_dataset_nfs" "parent-file.txt" "regular-dir/regular-file.txt" "child-file.txt"
    
    test_smb_visibility "parent_with_regular_dirs" "regular_dir_vs_dataset_smb" "parent-file.txt" "regular-dir/regular-file.txt" "child-file.txt"
    
    # Cleanup
    cleanup_all_exports
    
    log_success "Regular directory vs. dataset testing completed"
    return 0
}

# Function: test_real_datasets
# Description: Test the three real test cases
test_real_datasets() {
    log_header "Testing real dataset cases"
    
    local parent_dataset="${BASE_DATASET}/${TEST_PARENT}"
    local parent_path=$(sudo zfs get -H -o value mountpoint "${parent_dataset}")
    
    # Create baseline exports
    cleanup_all_exports
    create_nfs_export "${parent_path}" "real_datasets"
    create_smb_share "${parent_path}" "real_datasets"
    
    # Use the REGULAR_DIR_MARKER.txt file to check visibility
    for test_case in "${TEST_CASES[@]}"; do
        # Regular directory version
        test_nfs_visibility "${parent_path}" "real_regular_${test_case}_nfs" "regular-${test_case}/REGULAR_DIR_MARKER.txt"
        test_smb_visibility "real_datasets" "real_regular_${test_case}_smb" "regular-${test_case}/REGULAR_DIR_MARKER.txt"
        
        # Dataset version
        test_nfs_visibility "${parent_path}" "real_dataset_${test_case}_nfs" "test-${test_case}/${test_case}-file.txt"
        test_smb_visibility "real_datasets" "real_dataset_${test_case}_smb" "test-${test_case}/${test_case}-file.txt"
    done
    
    # Create individual exports for each test case
    cleanup_all_exports
    for test_case in "${TEST_CASES[@]}"; do
        local test_dataset="${parent_dataset}/test-${test_case}"
        local test_path=$(sudo zfs get -H -o value mountpoint "${test_dataset}")
        
        create_nfs_export "${test_path}" "individual_${test_case}"
        create_smb_share "${test_path}" "individual_${test_case}"
        
        # Test individual exports
        test_nfs_visibility "${test_path}" "individual_${test_case}_nfs" "${test_case}-file.txt"
        test_smb_visibility "individual_${test_case}" "individual_${test_case}_smb" "${test_case}-file.txt"
    done
    
    # Cleanup
    cleanup_all_exports
    
    log_success "Real dataset testing completed"
    return 0
}

# Function: test_property_combinations
# Description: Test various property combinations
test_property_combinations() {
    log_header "Testing property combinations"
    
    local parent_dataset="${BASE_DATASET}/${TEST_PARENT}"
    local child_dataset="${parent_dataset}/${TEST_CHILD}"
    local parent_path=$(sudo zfs get -H -o value mountpoint "${parent_dataset}")
    
    # Create baseline exports
    cleanup_all_exports
    create_nfs_export "${parent_path}" "property_combinations"
    
    # Test various combinations of properties
    log_info "Test 1: sharenfs=on, aclinherit=passthrough, acltype=posix"
    set_dataset_property "${parent_dataset}" "sharenfs" "on"

    # Add diagnostic info
    log_info "Checking current NFS exports:"
    sudo midclt call sharing.nfs.query | grep -v password | tee -a "${LOG_FILE}" || true
    log_info "Checking system NFS shares:"
    sudo showmount -e | tee -a "${LOG_FILE}" || true
    set_dataset_property "${child_dataset}" "sharenfs" "on"

    # Add diagnostic info
    log_info "Checking current NFS exports:"
    sudo midclt call sharing.nfs.query | grep -v password | tee -a "${LOG_FILE}" || true
    log_info "Checking system NFS shares:"
    sudo showmount -e | tee -a "${LOG_FILE}" || true
    set_dataset_property "${parent_dataset}" "aclinherit" "passthrough"
    set_dataset_property "${child_dataset}" "aclinherit" "passthrough"
    set_dataset_property "${parent_dataset}" "acltype" "posix"
    set_dataset_property "${child_dataset}" "acltype" "posix"
    
    # Test visibility
    test_nfs_visibility "${parent_path}" "combo_on_passthrough_posix" "parent-file.txt" "child-file.txt"
    
    # Test 2: sharenfs=on, aclinherit=restricted, acltype=nfsv4
    log_info "Test 2: sharenfs=on, aclinherit=restricted, acltype=nfsv4"
    set_dataset_property "${parent_dataset}" "aclinherit" "restricted"
    set_dataset_property "${child_dataset}" "aclinherit" "restricted"
    set_dataset_property "${parent_dataset}" "acltype" "nfsv4"
    set_dataset_property "${child_dataset}" "acltype" "nfsv4"
    
    # Test visibility
    test_nfs_visibility "${parent_path}" "combo_on_restricted_nfsv4" "parent-file.txt" "child-file.txt"
    
    # Reset to defaults
    set_dataset_property "${parent_dataset}" "sharenfs" "off"

    # Add diagnostic info
    log_info "Checking current NFS exports:"
    sudo midclt call sharing.nfs.query | grep -v password | tee -a "${LOG_FILE}" || true
    log_info "Checking system NFS shares:"
    sudo showmount -e | tee -a "${LOG_FILE}" || true
    set_dataset_property "${child_dataset}" "sharenfs" "off"

    # Add diagnostic info
    log_info "Checking current NFS exports:"
    sudo midclt call sharing.nfs.query | grep -v password | tee -a "${LOG_FILE}" || true
    log_info "Checking system NFS shares:"
    sudo showmount -e | tee -a "${LOG_FILE}" || true
    set_dataset_property "${parent_dataset}" "aclinherit" "restricted"
    set_dataset_property "${child_dataset}" "aclinherit" "restricted"
    set_dataset_property "${parent_dataset}" "acltype" "off"
    set_dataset_property "${child_dataset}" "acltype" "off"
    
    # Cleanup
    cleanup_all_exports
    
    log_success "Property combination testing completed"
    return 0
}

# Function: save_successful_configuration
# Description: Save configuration details for successful tests
save_successful_configuration() {
    log_header "Saving successful configurations"
    
    local results_file="${RESULT_DIR}/nested_dataset_results.txt"
    local success_file="${RESULT_DIR}/successful_configurations.md"
    
    if [ ! -f "${results_file}" ]; then
        log_warning "No results file found at ${results_file}"
        return 1
    fi
    
    # Initialize success file
    cat > "${success_file}" << EOF
# Successful NFS/SMB Configurations

Generated: $(date)

## NFS Configurations

| Test Name | Notes |
|-----------|-------|
EOF
    
    # Extract successful NFS tests
    grep "RESULT:NFS:.*:SUCCESS:" "${results_file}" | while IFS=: read -r result type test status details; do
        local parent_dataset="${BASE_DATASET}/${TEST_PARENT}"
        local child_dataset="${parent_dataset}/${TEST_CHILD}"
        
        # Get property values at time of success
        local sharenfs_parent=$(sudo zfs get -H -o value sharenfs "${parent_dataset}")
        local sharenfs_child=$(sudo zfs get -H -o value sharenfs "${child_dataset}")
        local aclinherit_parent=$(sudo zfs get -H -o value aclinherit "${parent_dataset}")
        local aclinherit_child=$(sudo zfs get -H -o value aclinherit "${child_dataset}")
        local acltype_parent=$(sudo zfs get -H -o value acltype "${parent_dataset}")
        local acltype_child=$(sudo zfs get -H -o value acltype "${child_dataset}")
        
        echo "| ${test} | ${details} |" >> "${success_file}"
        echo "| | Parent sharenfs=${sharenfs_parent}, Child sharenfs=${sharenfs_child} |" >> "${success_file}"
        echo "| | Parent aclinherit=${aclinherit_parent}, Child aclinherit=${aclinherit_child} |" >> "${success_file}"
        echo "| | Parent acltype=${acltype_parent}, Child acltype=${acltype_child} |" >> "${success_file}"
    done
    
    # Add SMB section
    cat >> "${success_file}" << EOF

## SMB Configurations

| Test Name | Notes |
|-----------|-------|
EOF
    
    # Extract successful SMB tests
    grep "RESULT:SMB:.*:SUCCESS:" "${results_file}" | while IFS=: read -r result type test status details; do
        local parent_dataset="${BASE_DATASET}/${TEST_PARENT}"
        local child_dataset="${parent_dataset}/${TEST_CHILD}"
        
        # Get property values at time of success
        local sharesmb_parent=$(sudo zfs get -H -o value sharesmb "${parent_dataset}")
        local sharesmb_child=$(sudo zfs get -H -o value sharesmb "${child_dataset}")
        local aclinherit_parent=$(sudo zfs get -H -o value aclinherit "${parent_dataset}")
        local aclinherit_child=$(sudo zfs get -H -o value aclinherit "${child_dataset}")
        local acltype_parent=$(sudo zfs get -H -o value acltype "${parent_dataset}")
        local acltype_child=$(sudo zfs get -H -o value acltype "${child_dataset}")
        
        echo "| ${test} | ${details} |" >> "${success_file}"
        echo "| | Parent sharesmb=${sharesmb_parent}, Child sharesmb=${sharesmb_child} |" >> "${success_file}"
        echo "| | Parent aclinherit=${aclinherit_parent}, Child aclinherit=${aclinherit_child} |" >> "${success_file}"
        echo "| | Parent acltype=${acltype_parent}, Child acltype=${acltype_child} |" >> "${success_file}"
    done
    
    log_success "Successful configurations saved to ${success_file}"
    return 0
}
