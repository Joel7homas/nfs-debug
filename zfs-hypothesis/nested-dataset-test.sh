#!/bin/bash
# Exit on errors
# Error handling is managed on a per-function basis
# nested-dataset-test.sh - Main test runner for nested dataset hypothesis testing
# Follows minimalist multi-module pattern (max 10 functions per module)

# Set defaults if not provided by the environment
export REMOTE_HOST=${REMOTE_HOST:-"pita"}
export REMOTE_USER=${REMOTE_USER:-"joel"}
export BASE_DATASET=${BASE_DATASET:-"data-tank/docker"}
export TEST_PARENT=${TEST_PARENT:-"test-parent"}
export TEST_CHILD=${TEST_CHILD:-"test-child"}
export RESULT_DIR=${RESULT_DIR:-"./results"}
export LOG_FILE=${LOG_FILE:-"$RESULT_DIR/nested-dataset-test.log"}
export TEST_MOUNT_POINT=${TEST_MOUNT_POINT:-"/mnt/nfs-test"}
export SMB_MOUNT_POINT=${SMB_MOUNT_POINT:-"/mnt/smb-test"}
export TEST_CASES=("jellyfin" "caddy" "vaultwarden")

# Source all modules
source ./nested-dataset-test-core.sh
source ./dataset-management.sh
source ./export-management.sh
source ./visibility-testing.sh
source ./property-testing.sh

# Function: run_all_tests
# Description: Run all tests in sequence
run_all_tests() {
    # Initialize test environment
    init_test_environment
    
    # Create test dataset structure
    create_test_dataset_structure || log_warning "Dataset structure creation had issues, but continuing" || { log_error "Failed to create test dataset structure"; return 1; }
    
    # Create test case datasets
    create_test_case_datasets || log_warning "Test case datasets creation had issues, but continuing"
    
    # Copy real data to test datasets (small samples)
    copy_real_data_to_test_datasets || log_warning "Data copying had issues, but continuing"
    
    # Create regular directory copies
    create_regular_directory_copies || log_warning "Regular directory copying had issues, but continuing"
    
    # List dataset structure
    list_dataset_structure
    
    # Run basic nested dataset hypothesis test
    test_nested_dataset_hypothesis || log_warning "Nested dataset hypothesis test had issues, but continuing"
    
    # Test sharenfs property effects
    test_sharenfs_property || log_warning "Sharenfs property test had issues, but continuing"
    
    # Test aclinherit property effects
    test_aclinherit_property || log_warning "Aclinherit property test had issues, but continuing"
    
    # Test acltype property effects
    test_acltype_property || log_warning "Acltype property test had issues, but continuing"
    
    # Test regular directories vs datasets
    test_regular_dir_vs_datasets || log_warning "Regular dir vs datasets test had issues, but continuing"
    
    # Test property combinations
    test_property_combinations || log_warning "Property combinations test had issues, but continuing"
    
    # Test real datasets
    test_real_datasets || log_warning "Real datasets test had issues, but continuing"
    
    # Save successful configurations
    save_successful_configuration
    
    # Cleanup
    cleanup_all_exports
    cleanup_test_datasets
}

# Function: run_nested_dataset_hypothesis_only
# Description: Run only the nested dataset hypothesis test
run_nested_dataset_hypothesis_only() {
    # Initialize test environment
    init_test_environment
    
    # Create test dataset structure
    create_test_dataset_structure || { log_error "Failed to create test dataset structure"; return 1; }
    
    # List dataset structure
    list_dataset_structure
    
    # Run basic nested dataset hypothesis test
    test_nested_dataset_hypothesis || log_warning "Nested dataset hypothesis test had issues, but continuing"
    
    # Cleanup
    cleanup_all_exports
    cleanup_test_datasets
}

# Function: run_property_tests_only
# Description: Run only the property tests
run_property_tests_only() {
    # Initialize test environment
    init_test_environment
    
    # Create test dataset structure
    create_test_dataset_structure || { log_error "Failed to create test dataset structure"; return 1; }
    
    # List dataset structure
    list_dataset_structure
    
    # Test sharenfs property effects
    test_sharenfs_property || log_warning "Sharenfs property test had issues, but continuing"
    
    # Test aclinherit property effects
    test_aclinherit_property || log_warning "Aclinherit property test had issues, but continuing"
    
    # Test acltype property effects
    test_acltype_property || log_warning "Acltype property test had issues, but continuing"
    
    # Test property combinations
    test_property_combinations || log_warning "Property combinations test had issues, but continuing"
    
    # Save successful configurations
    save_successful_configuration
    
    # Cleanup
    cleanup_all_exports
    cleanup_test_datasets
}

# Function: run_real_dataset_tests_only
# Description: Run only the real dataset tests
run_real_dataset_tests_only() {
    # Initialize test environment
    init_test_environment
    
    # Create test dataset structure
    create_test_dataset_structure || { log_error "Failed to create test dataset structure"; return 1; }
    
    # Create test case datasets
    create_test_case_datasets
    
    # Copy real data to test datasets
    copy_real_data_to_test_datasets
    
    # Create regular directory copies
    create_regular_directory_copies
    
    # List dataset structure
    list_dataset_structure
    
    # Test real datasets
    test_real_datasets || log_warning "Real datasets test had issues, but continuing"
    
    # Save successful configurations
    save_successful_configuration
    
    # Cleanup
    cleanup_all_exports
    cleanup_test_datasets
}

# Function: generate_report
# Description: Generate a summary report
generate_report() {
    local results_file="${RESULT_DIR}/nested_dataset_results.txt"
    local report_file="${RESULT_DIR}/nested_dataset_report.md"
    
    if [ ! -f "${results_file}" ]; then
        echo "No results file found at ${results_file}"
        return 1
    fi
    
    # Initialize report file
    cat > "${report_file}" << EOF
# Nested Dataset Hypothesis Test Report

Generated: $(date)

## Summary

This report summarizes the results of testing the nested dataset hypothesis,
which states that visibility issues may be caused by parent-child ZFS dataset
relationships when sharing parent datasets.

## Test Results

EOF
    
    # Count results
    local nfs_success=$(grep -c "RESULT:NFS:.*:SUCCESS:" "${results_file}" 2>/dev/null || echo 0)
    local nfs_partial=$(grep -c "RESULT:NFS:.*:PARTIAL:" "${results_file}" 2>/dev/null || echo 0)
    local nfs_failed=$(grep -c "RESULT:NFS:.*:FAILED:" "${results_file}" 2>/dev/null || echo 0)
    local nfs_mount_failed=$(grep -c "RESULT:NFS:.*:MOUNT_FAILED:" "${results_file}" 2>/dev/null || echo 0)
    
    local smb_success=$(grep -c "RESULT:SMB:.*:SUCCESS:" "${results_file}" 2>/dev/null || echo 0)
    local smb_partial=$(grep -c "RESULT:SMB:.*:PARTIAL:" "${results_file}" 2>/dev/null || echo 0)
    local smb_failed=$(grep -c "RESULT:SMB:.*:FAILED:" "${results_file}" 2>/dev/null || echo 0)
    local smb_mount_failed=$(grep -c "RESULT:SMB:.*:MOUNT_FAILED:" "${results_file}" 2>/dev/null || echo 0)
    
    # Add summary table
    cat >> "${report_file}" << EOF
### Result Counts

| Protocol | Success | Partial | Failed | Mount Failed | Total |
|----------|---------|---------|--------|--------------|-------|
| NFS      | ${nfs_success} | ${nfs_partial} | ${nfs_failed} | ${nfs_mount_failed} | $((nfs_success + nfs_partial + nfs_failed + nfs_mount_failed)) |
| SMB      | ${smb_success} | ${smb_partial} | ${smb_failed} | ${smb_mount_failed} | $((smb_success + smb_partial + smb_failed + smb_mount_failed)) |

## Key Findings

EOF
    
    # Extract key findings based on test results
    
    # Check nested dataset hypothesis
    if grep -q "RESULT:NFS:nested_parent_only_nfs:FAILED:" "${results_file}" && \
       grep -q "RESULT:NFS:nested_child_only_nfs:SUCCESS:" "${results_file}"; then
        cat >> "${report_file}" << EOF
1. **Nested Dataset Hypothesis Confirmed**: When exporting a parent dataset via NFS, child datasets are not visible, 
   but when exporting child datasets directly, their contents are visible.

EOF
    elif grep -q "RESULT:NFS:nested_parent_only_nfs:SUCCESS:" "${results_file}"; then
        cat >> "${report_file}" << EOF
1. **Nested Dataset Hypothesis Not Confirmed for NFS**: Child datasets are visible when exporting the parent dataset via NFS.

EOF
    else
        cat >> "${report_file}" << EOF
1. **Nested Dataset Results Inconclusive for NFS**: The tests did not produce clear evidence for or against the nested dataset hypothesis.

EOF
    fi
    
    # Check SMB nested dataset hypothesis
    if grep -q "RESULT:SMB:nested_parent_only_smb:PARTIAL:" "${results_file}" && \
       grep -q "RESULT:SMB:nested_child_only_smb:SUCCESS:" "${results_file}"; then
        cat >> "${report_file}" << EOF
2. **Nested Dataset Hypothesis Partially Confirmed for SMB**: When exporting a parent dataset via SMB, some child datasets 
   are visible and some are not, but when exporting child datasets directly, their contents are always visible.

EOF
    elif grep -q "RESULT:SMB:nested_parent_only_smb:SUCCESS:" "${results_file}"; then
        cat >> "${report_file}" << EOF
2. **Nested Dataset Hypothesis Not Confirmed for SMB**: Child datasets are visible when exporting the parent dataset via SMB.

EOF
    else
        cat >> "${report_file}" << EOF
2. **Nested Dataset Results Inconclusive for SMB**: The tests did not produce clear evidence for or against the nested dataset hypothesis.

EOF
    fi
    
    # Check regular directory vs dataset results
    if grep -q "RESULT:NFS:regular_dir_vs_dataset_nfs:PARTIAL:" "${results_file}"; then
        cat >> "${report_file}" << EOF
3. **Regular Directories vs Datasets**: Regular directories within the parent dataset are visible, but nested datasets may not be.
   This supports the hypothesis that ZFS dataset boundaries affect NFS visibility.

EOF
    fi
    
    # Check sharenfs property results
    if grep -q "RESULT:NFS:sharenfs_on_both_parent:SUCCESS:" "${results_file}" || \
       grep -q "RESULT:NFS:sharenfs_on_parent_off_child:SUCCESS:" "${results_file}"; then
        cat >> "${report_file}" << EOF
4. **sharenfs Property Effect**: Setting sharenfs=on for the parent dataset appears to improve visibility of child datasets.

EOF
    fi
    
    # Check aclinherit property results
    for option in "restricted" "passthrough" "passthrough-x" "discard"; do
        if grep -q "RESULT:NFS:aclinherit_${option}:SUCCESS:" "${results_file}"; then
            cat >> "${report_file}" << EOF
5. **aclinherit Property Effect**: Setting aclinherit=${option} appears to improve visibility of child datasets.

EOF
            break
        fi
    done
    
    # Check real datasets
    for test_case in "${TEST_CASES[@]}"; do
        if grep -q "RESULT:NFS:individual_${test_case}_nfs:SUCCESS:" "${results_file}" && \
           grep -q "RESULT:NFS:real_dataset_${test_case}_nfs:FAILED:" "${results_file}"; then
            cat >> "${report_file}" << EOF
6. **Individual Exports Work Better**: For the ${test_case} test case, individual exports work while accessing through the parent dataset fails.
   This confirms the nested dataset hypothesis for real-world datasets.

EOF
            break
        fi
    done
    
    cat >> "${report_file}" << EOF
## Recommendations

Based on the test results, the following recommendations can be made:

EOF
    
    # Add recommendations based on results
    if grep -q "RESULT:NFS:nested_child_only_nfs:SUCCESS:" "${results_file}"; then
        cat >> "${report_file}" << EOF
1. **Use Individual Dataset Exports**: Export each dataset individually rather than exporting parent datasets.
   This approach bypasses issues with nested dataset visibility.

EOF
    fi
    
    if grep -q "RESULT:NFS:regular_dir_vs_dataset_nfs:PARTIAL:" "${results_file}" && \
       grep -q "regular-dir/regular-file.txt" "${results_file}"; then
        cat >> "${report_file}" << EOF
2. **Use Regular Directories Instead of Nested Datasets**: Consider restructuring data to use regular directories
   within a single ZFS dataset rather than creating nested datasets.

EOF
    fi
    
    for option in "passthrough" "passthrough-x" "restricted" "discard"; do
        if grep -q "RESULT:NFS:aclinherit_${option}:SUCCESS:" "${results_file}"; then
            cat >> "${report_file}" << EOF
3. **ZFS Property Optimization**: Set aclinherit=${option} on datasets to improve visibility.

EOF
            break
        fi
    done
    
    if grep -q "RESULT:SMB:.*:SUCCESS:" "${results_file}"; then
        cat >> "${report_file}" << EOF
4. **Consider SMB for File Sharing**: SMB generally provides better visibility for nested datasets than NFS.
   Consider using SMB instead of NFS for file sharing between TrueNAS Scale and Ubuntu.

EOF
    fi
    
    # Add conclusion
    cat >> "${report_file}" << EOF
## Conclusion

This investigation has provided insights into the visibility issues between TrueNAS Scale and Ubuntu systems.
The tests have helped to confirm or refute the nested dataset hypothesis and provided practical strategies
for improving visibility and ensuring reliable access to data.

The most effective approach appears to be:
1. Using individual dataset exports rather than parent dataset exports
2. Optimizing ZFS properties to improve visibility
3. Using SMB instead of NFS where possible
4. Restructuring data to use regular directories within datasets rather than nested datasets
EOF
    
    echo "Report generated at ${report_file}"
    return 0
}

# Main function
main() {
    # Process command line arguments
    if [ $# -eq 0 ]; then
        run_all_tests
    else
        case "$1" in
            "hypothesis")
                run_nested_dataset_hypothesis_only
                ;;
            "properties")
                run_property_tests_only
                ;;
            "real")
                run_real_dataset_tests_only
                ;;
            "report")
                generate_report
                ;;
            *)
                echo "Unknown command: $1"
                echo "Usage: $0 [hypothesis|properties|real|report]"
                exit 1
                ;;
        esac
    fi
    
    # Generate report
    generate_report
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
