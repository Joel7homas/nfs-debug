#!/bin/bash
# NFS Solutions Tester - Part 3
# Functions for more specialized NFS tests

# Test autofs solution
test_autofs() {
    header "Testing autofs solution"
    
    # Install autofs if needed
    if ! command -v automount &> /dev/null; then
        log "Installing autofs package"
        sudo apt-get update -qq
        sudo apt-get install -y autofs
    fi
    
    local autofs_dir="/autofs/nfs-test"
    local autofs_master="/etc/auto.master.d/nfs-test.autofs"
    local autofs_map="/etc/auto.nfs-test"
    
    # Create backup of existing configs if they exist
    if [ -f "$autofs_master" ]; then
        sudo cp "$autofs_master" "${autofs_master}.bak"
    fi
    if [ -f "$autofs_map" ]; then
        sudo cp "$autofs_map" "${autofs_map}.bak"
    fi
    
    # Create autofs configuration
    log "Creating autofs configuration"
    sudo mkdir -p /etc/auto.master.d
    echo "/autofs /etc/auto.nfs-test --timeout=60" | sudo tee "$autofs_master" > /dev/null
    echo "nfs-test -fstype=nfs,rw,hard,intr,noatime $NFS_SERVER:$NFS_EXPORT" | sudo tee "$autofs_map" > /dev/null
    
    # Restart autofs
    log "Restarting autofs service"
    sudo systemctl restart autofs
    
    # Wait for autofs to initialize
    sleep 2
    
    # Create mount point directory if it doesn't exist
    sudo mkdir -p /autofs
    
    # Try to access the mount
    log "Testing autofs mount"
    sudo mkdir -p "$autofs_dir"
    
    if [ -d "$autofs_dir" ]; then
        log "Autofs directory created"
        
        # Try to list the directory to trigger mount
        ls -la "$autofs_dir" > /dev/null 2>&1
        
        # Check if mounted
        if mount | grep -q "$autofs_dir"; then
            log "Autofs mount successful"
            
            # Check content
            local check_result
            local original_temp="$TEMP_MOUNT"
            TEMP_MOUNT="$autofs_dir"
            check_content
            check_result=$?
            TEMP_MOUNT="$original_temp"
            
            # Record results
            if [ $check_result -eq 0 ]; then
                result "✅ SUCCESS: Autofs mount"
                result "  - Configuration: /etc/auto.master.d/nfs-test.autofs"
                result "  - Map: /etc/auto.nfs-test"
                result "  - All test directories visible"
                result ""
            elif [ $check_result -eq 2 ]; then
                result "⚠️ PARTIAL: Autofs mount"
                result "  - Configuration: /etc/auto.master.d/nfs-test.autofs"
                result "  - Map: /etc/auto.nfs-test"
                result "  - Some test directories visible"
                result ""
            else
                result "❌ FAILED: Autofs mount"
                result "  - Configuration: /etc/auto.master.d/nfs-test.autofs"
                result "  - Map: /etc/auto.nfs-test"
                result "  - Mount successful but no content visible"
                result ""
            fi
        else
            error "Autofs mount not triggered"
            result "❌ FAILED: Autofs mount"
            result "  - Mount not triggered"
            result ""
        fi
    else
        error "Failed to create autofs directory"
        result "❌ FAILED: Autofs mount"
        result "  - Directory creation failed"
        result ""
    fi
    
    # Cleanup
    log "Cleaning up autofs configuration"
    if [ -f "${autofs_master}.bak" ]; then
        sudo mv "${autofs_master}.bak" "$autofs_master"
    else
        sudo rm -f "$autofs_master"
    fi
    
    if [ -f "${autofs_map}.bak" ]; then
        sudo mv "${autofs_map}.bak" "$autofs_map"
    else
        sudo rm -f "$autofs_map"
    fi
    
    sudo systemctl restart autofs
    
    return $check_result
}

# Test mount with nfs-idmapd configuration
test_idmap_config() {
    header "Testing NFS with custom idmapd configuration"
    
    # Backup existing idmapd.conf
    if [ -f /etc/idmapd.conf ]; then
        sudo cp /etc/idmapd.conf /etc/idmapd.conf.bak
    fi
    
    # Create custom idmapd.conf
    log "Creating custom idmapd.conf"
    cat << EOF | sudo tee /etc/idmapd.conf > /dev/null
[General]
Verbosity = 0
Pipefs-Directory = /run/rpc_pipefs
Domain = local

[Mapping]
Nobody-User = nobody
Nobody-Group = nogroup

[Translation]
Method = nsswitch

[Static]
root@babka.7homas.com = $(id -un)
root@* = $(id -un)
* = %(owner)
EOF
    
    # Restart idmapd
    log "Restarting nfs-idmapd service"
    sudo systemctl restart nfs-idmapd
    
    # Test NFS mount with NFSv4
    log "Testing NFSv4 mount with updated idmapd.conf"
    cleanup_mounts
    
    if sudo mount -t nfs4 -o sec=sys,rw "$NFS_SERVER:$NFS_EXPORT" "$TEMP_MOUNT"; then
        log "Mount successful"
        
        # Check content
        local check_result
        check_content
        check_result=$?
        
        # Record results
        if [ $check_result -eq 0 ]; then
            result "✅ SUCCESS: NFSv4 with custom idmapd.conf"
            result "  - Command: mount -t nfs4 -o sec=sys,rw $NFS_SERVER:$NFS_EXPORT /mount/point"
            result "  - Custom idmapd.conf configuration"
            result "  - All test directories visible"
            result ""
        elif [ $check_result -eq 2 ]; then
            result "⚠️ PARTIAL: NFSv4 with custom idmapd.conf"
            result "  - Command: mount -t nfs4 -o sec=sys,rw $NFS_SERVER:$NFS_EXPORT /mount/point"
            result "  - Custom idmapd.conf configuration"
            result "  - Some test directories visible"
            result ""
        else
            result "❌ FAILED: NFSv4 with custom idmapd.conf"
            result "  - Command: mount -t nfs4 -o sec=sys,rw $NFS_SERVER:$NFS_EXPORT /mount/point"
            result "  - Custom idmapd.conf configuration"
            result "  - Mount successful but no content visible"
            result ""
        fi
        
        # Unmount
        sudo umount "$TEMP_MOUNT"
    else
        error "Mount failed"
        result "❌ FAILED: NFSv4 with custom idmapd.conf"
        result "  - Mount command failed"
        result ""
    fi
    
    # Restore original idmapd.conf
    if [ -f /etc/idmapd.conf.bak ]; then
        sudo mv /etc/idmapd.conf.bak /etc/idmapd.conf
        sudo systemctl restart nfs-idmapd
    fi
    
    return $check_result
}

# Test individual directories
test_individual_dirs() {
    header "Testing individual directory mounts"
    
    local successful_dirs=()
    local failed_dirs=()
    
    for dir in "${TEST_DIRS[@]}"; do
        local test_mount="/mnt/test-${dir}"
        
        log "Testing directory: $dir"
        
        # Create mount point
        sudo mkdir -p "$test_mount"
        
        # Try to mount
        if sudo mount -t nfs "$NFS_SERVER:$NFS_EXPORT/$dir" "$test_mount"; then
            log "Mount successful for $dir"
            
            # Check for content
            local count=$(find "$test_mount" -type f 2>/dev/null | wc -l)
            if [ "$count" -gt 0 ]; then
                success "$dir has $count files visible"
                successful_dirs+=("$dir")
            else
                error "$dir shows no files"
                failed_dirs+=("$dir")
            fi
            
            # Unmount
            sudo umount "$test_mount"
        else
            error "Failed to mount $dir"
            failed_dirs+=("$dir")
        fi
        
        # Remove mount point
        sudo rmdir "$test_mount"
    done
    
    # Record results
    if [ ${#successful_dirs[@]} -eq ${#TEST_DIRS[@]} ]; then
        result "✅ SUCCESS: Individual directory mounts"
        result "  - All directories can be mounted individually"
        result "  - This confirms the issue is with parent directory mount only"
        result ""
        return 0
    elif [ ${#successful_dirs[@]} -gt 0 ]; then
        result "⚠️ PARTIAL: Individual directory mounts"
        result "  - Working directories: ${successful_dirs[*]}"
        result "  - Failed directories: ${failed_dirs[*]}"
        result ""
        return 2
    else
        result "❌ FAILED: Individual directory mounts"
        result "  - No directories can be mounted individually"
        result ""
        return 1
    fi
}

# Test NFS with specific client-side sysctl params
test_sysctl_params() {
    header "Testing with modified sysctl parameters"
    
    # Backup current settings
    local current_timeout=$(sysctl -n fs.nfs.nlm_timeout 2>/dev/null || echo "NA")
    local current_udp_slot=$(sysctl -n sunrpc.udp_slot_table_entries 2>/dev/null || echo "NA")
    local current_tcp_slot=$(sysctl -n sunrpc.tcp_slot_table_entries 2>/dev/null || echo "NA")
    
    log "Current sysctl params:"
    log "- fs.nfs.nlm_timeout: $current_timeout"
    log "- sunrpc.udp_slot_table_entries: $current_udp_slot"
    log "- sunrpc.tcp_slot_table_entries: $current_tcp_slot"
    
    # Set new values
    log "Setting new sysctl parameters"
    sudo sysctl -w fs.nfs.nlm_timeout=30 > /dev/null
    sudo sysctl -w sunrpc.udp_slot_table_entries=128 > /dev/null
    sudo sysctl -w sunrpc.tcp_slot_table_entries=128 > /dev/null
    
    # Test mount
    cleanup_mounts
    
    if sudo mount -t nfs -o rw,hard "$NFS_SERVER:$NFS_EXPORT" "$TEMP_MOUNT"; then
        log "Mount successful with modified sysctl parameters"
        
        # Check content
        local check_result
        check_content
        check_result=$?
        
        # Record results
        if [ $check_result -eq 0 ]; then
            result "✅ SUCCESS: Modified sysctl parameters"
            result "  - fs.nfs.nlm_timeout=30"
            result "  - sunrpc.udp_slot_table_entries=128"
            result "  - sunrpc.tcp_slot_table_entries=128"
            result "  - All test directories visible"
            result ""
        elif [ $check_result -eq 2 ]; then
            result "⚠️ PARTIAL: Modified sysctl parameters"
            result "  - fs.nfs.nlm_timeout=30"
            result "  - sunrpc.udp_slot_table_entries=128"
            result "  - sunrpc.tcp_slot_table_entries=128"
            result "  - Some test directories visible"
            result ""
        else
            result "❌ FAILED: Modified sysctl parameters"
            result "  - fs.nfs.nlm_timeout=30"
            result "  - sunrpc.udp_slot_table_entries=128"
            result "  - sunrpc.tcp_slot_table_entries=128"
            result "  - Mount successful but no content visible"
            result ""
        fi
        
        # Unmount
        sudo umount "$TEMP_MOUNT"
    else
        error "Mount failed with modified sysctl parameters"
        result "❌ FAILED: Modified sysctl parameters"
        result "  - Mount command failed"
        result ""
    fi
    
    # Restore original values if they were available
    log "Restoring original sysctl parameters"
    if [ "$current_timeout" != "NA" ]; then
        sudo sysctl -w fs.nfs.nlm_timeout="$current_timeout" > /dev/null
    fi
    if [ "$current_udp_slot" != "NA" ]; then
        sudo sysctl -w sunrpc.udp_slot_table_entries="$current_udp_slot" > /dev/null
    fi
    if [ "$current_tcp_slot" != "NA" ]; then
        sudo sysctl -w sunrpc.tcp_slot_table_entries="$current_tcp_slot" > /dev/null
    fi
    
    return $check_result
}
