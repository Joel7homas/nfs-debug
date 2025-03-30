#!/bin/bash
# client-mount-nfs.sh - NFS-specific client mount testing functions
# Implements the minimalist multi-module pattern (max 10 functions per module)

# Ensure we have core utilities
if ! type log_info &> /dev/null; then
    echo "ERROR: utils-core.sh must be sourced before client-mount-nfs.sh"
    exit 1
fi

# Ensure we have client-mount-core
if ! type test_mount_with_options &> /dev/null; then
    echo "ERROR: client-mount-core.sh must be sourced before client-mount-nfs.sh"
    exit 1
fi

# Function: test_nfs_v3_basic
# Description: Test basic NFSv3 mount
test_nfs_v3_basic() {
    test_mount_with_options "rw,hard" "" "NFSv3 Basic"
    return $?
}

# Function: test_nfs_v4_basic
# Description: Test basic NFSv4 mount
test_nfs_v4_basic() {
    test_mount_with_options "rw,hard" "4" "NFSv4 Basic"
    return $?
}

# Function: test_nfs_v3_no_cache
# Description: Test NFSv3 mount with caching disabled
test_nfs_v3_no_cache() {
    test_mount_with_options "rw,hard,noac" "" "NFSv3 No Cache"
    return $?
}

# Function: test_nfs_v4_no_cache
# Description: Test NFSv4 mount with caching disabled
test_nfs_v4_no_cache() {
    test_mount_with_options "rw,hard,noac" "4" "NFSv4 No Cache"
    return $?
}

# Function: test_nfs_v3_actimeo
# Description: Test NFSv3 mount with attribute caching timeout
test_nfs_v3_actimeo() {
    test_mount_with_options "rw,hard,actimeo=0" "" "NFSv3 actimeo=0"
    return $?
}

# Function: test_nfs_v3_lookupcache
# Description: Test NFSv3 mount with lookupcache options
test_nfs_v3_lookupcache() {
    test_mount_with_options "rw,hard,lookupcache=none" "" "NFSv3 lookupcache=none"
    return $?
}

# Function: test_nfs_v3_all_options
# Description: Test NFSv3 mount with all caching options disabled
test_nfs_v3_all_options() {
    test_mount_with_options "rw,hard,noac,actimeo=0,lookupcache=none" "" "NFSv3 All Cache Options"
    return $?
}

# Function: test_nfs_v3_suid
# Description: Test NFSv3 mount with nosuid option
test_nfs_v3_suid() {
    test_mount_with_options "rw,hard,nosuid" "" "NFSv3 nosuid"
    return $?
}

# Function: test_nfs_v3_size_options
# Description: Test NFSv3 mount with specific rsize/wsize
test_nfs_v3_size_options() {
    test_mount_with_options "rw,hard,rsize=1048576,wsize=1048576" "" "NFSv3 with rsize/wsize"
    return $?
}

# Function: test_nfs_client_mounts
# Description: Run all NFS client mount tests
test_nfs_client_mounts() {
    log_header "Testing NFS client mount options"
    
    # Ensure results directory exists
    mkdir -p "${RESULT_DIR}"
    
    # Run client information gathering
    remote_client_info
    check_remote_nfs_client_config
    
    # Run all the tests
    test_nfs_v3_basic
    test_nfs_v4_basic
    test_nfs_v3_no_cache
    test_nfs_v4_no_cache
    test_nfs_v3_actimeo
    test_nfs_v3_lookupcache
    test_nfs_v3_all_options
    test_nfs_v3_suid
    test_nfs_v3_size_options
    
    log_success "All NFS client mount tests completed"
    
    # Generate summary
    local success_count=$(grep -c "RESULT:MOUNT:.*:SUCCESS" "${RESULT_DIR}/mount_results.log")
    local partial_count=$(grep -c "RESULT:MOUNT:.*:PARTIAL" "${RESULT_DIR}/mount_results.log")
    local failed_count=$(grep -c "RESULT:MOUNT:.*:FAILED\|RESULT:MOUNT:.*:NO_CONTENT" "${RESULT_DIR}/mount_results.log")
    
    log_info "Summary: $success_count successful, $partial_count partial, $failed_count failed mounts"
    
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
    test_nfs_client_mounts
fi
