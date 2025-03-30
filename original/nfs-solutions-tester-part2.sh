#!/bin/bash
# NFS Solutions Tester - Part 2
# Functions for bindfs and loopback NFS testing

# Test bindfs with different configurations
test_bindfs_mount() {
    local description="$1"
    local nfs_options="$2"
    local bindfs_options="$3"
    local nfs_version="$4"
    local bind_mount="/mnt/bindfs-test"
    
    header "Testing bindfs: $description"
    log "NFS options: $nfs_options"
    log "Bindfs options: $bindfs_options"
    
    # Ensure we start clean
    cleanup_mounts
    if [ -d "$bind_mount" ]; then
        sudo umount -f "$bind_mount" 2>/dev/null || true
    else
        sudo mkdir -p "$bind_mount"
    fi
    
    # Mount NFS
    log "Mounting NFS share to temporary location..."
    if ! sudo mount -t "nfs$nfs_version" -o "$nfs_options" "$NFS_SERVER:$NFS_EXPORT" "$TEMP_MOUNT"; then
        error "Failed to mount NFS share. Skipping bindfs test."
        
        result "❌ FAILED: Bindfs - $description"
        result "  - NFS mount failed"
        result ""
        
        return 1
    fi
    
    log "NFS mounted successfully. Creating bindfs mount..."
    
    # Try bindfs mount
    if sudo bindfs $bindfs_options "$TEMP_MOUNT" "$bind_mount"; then
        log "Bindfs mount successful"
        
        # Check content visibility
        local check_result
        local original_temp="$TEMP_MOUNT"
        TEMP_MOUNT="$bind_mount"
        check_content
        check_result=$?
        TEMP_MOUNT="$original_temp"
        
        # Record results
        if [ $check_result -eq 0 ]; then
            result "✅ SUCCESS: Bindfs - $description"
            result "  - NFS: mount -t nfs$nfs_version -o $nfs_options $NFS_SERVER:$NFS_EXPORT /temp/mount"
            result "  - Bindfs: bindfs $bindfs_options /temp/mount /final/mount"
            result "  - All test directories visible"
            result ""
        elif [ $check_result -eq 2 ]; then
            result "⚠️ PARTIAL: Bindfs - $description"
            result "  - NFS: mount -t nfs$nfs_version -o $nfs_options $NFS_SERVER:$NFS_EXPORT /temp/mount"
            result "  - Bindfs: bindfs $bindfs_options /temp/mount /final/mount"
            result "  - Some test directories visible"
            result ""
        else
            result "❌ FAILED: Bindfs - $description"
            result "  - NFS: mount -t nfs$nfs_version -o $nfs_options $NFS_SERVER:$NFS_EXPORT /temp/mount"
            result "  - Bindfs: bindfs $bindfs_options /temp/mount /final/mount"
            result "  - Mount successful but no content visible"
            result ""
        fi
        
        # Cleanup
        log "Unmounting bindfs..."
        sudo umount "$bind_mount"
        
        return $check_result
    else
        error "Bindfs mount failed"
        
        result "❌ FAILED: Bindfs - $description"
        result "  - NFS mount succeeded"
        result "  - Bindfs mount failed"
        result ""
        
        return 1
    fi
}

# Test loopback NFS mount
test_loopback_nfs() {
    header "Testing loopback NFS mount"
    
    local loopback_export="/tmp/nfs-export"
    local loopback_mount="/tmp/nfs-loopback"
    
    log "Creating temporary loopback export directory"
    sudo mkdir -p "$loopback_export"
    
    # Mount the original NFS share
    cleanup_mounts
    log "Mounting original NFS share"
    if ! sudo mount -t nfs "$NFS_SERVER:$NFS_EXPORT" "$TEMP_MOUNT"; then
        error "Failed to mount original NFS share"
        return 1
    fi
    
    # Bind mount to loopback export
    log "Creating bind mount for loopback export"
    if ! sudo mount --bind "$TEMP_MOUNT" "$loopback_export"; then
        error "Failed to create bind mount"
        sudo umount "$TEMP_MOUNT"
        return 1
    fi
    
    # Create loopback mount point
    sudo mkdir -p "$loopback_mount"
    
    # Install NFS server if needed
    if ! command -v exportfs &> /dev/null; then
        log "Installing NFS server packages"
        sudo apt-get update -qq
        sudo apt-get install -y nfs-kernel-server
    fi
    
    # Export loopback directory
    log "Creating temporary NFS export"
    echo "$loopback_export *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee /etc/exports.d/temp.exports > /dev/null
    sudo exportfs -ra
    
    # Mount the loopback export
    log "Mounting loopback NFS export"
    if sudo mount -t nfs localhost:"$loopback_export" "$loopback_mount"; then
        log "Loopback mount successful"
        
        # Check content
        local check_result
        local original_temp="$TEMP_MOUNT"
        TEMP_MOUNT="$loopback_mount"
        check_content
        check_result=$?
        TEMP_MOUNT="$original_temp"
        
        # Record results
        if [ $check_result -eq 0 ]; then
            result "✅ SUCCESS: Loopback NFS mount"
            result "  - Re-export original NFS via local NFS server"
            result "  - All test directories visible"
            result ""
        elif [ $check_result -eq 2 ]; then
            result "⚠️ PARTIAL: Loopback NFS mount"
            result "  - Re-export original NFS via local NFS server"
            result "  - Some test directories visible"
            result ""
        else
            result "❌ FAILED: Loopback NFS mount"
            result "  - Re-export original NFS via local NFS server"
            result "  - Mount successful but no content visible"
            result ""
        fi
    else
        error "Loopback mount failed"
        result "❌ FAILED: Loopback NFS mount"
        result "  - Re-export failed"
        result ""
    fi
    
    # Cleanup
    log "Cleaning up loopback NFS"
    sudo umount "$loopback_mount" 2>/dev/null || true
    sudo umount "$loopback_export" 2>/dev/null || true
    sudo umount "$TEMP_MOUNT" 2>/dev/null || true
    sudo rm -f /etc/exports.d/temp.exports
    sudo exportfs -ra
    
    return $check_result
}

# Test unionfs/mergerfs approach
test_unionfs() {
    header "Testing unionfs/mergerfs approach"
    
    # Check if mergerfs is installed
    if ! command -v mergerfs &> /dev/null; then
        log "Installing mergerfs package"
        sudo apt-get update -qq
        sudo apt-get install -y mergerfs
    fi
    
    # Create temporary directories
    local merge_mount="/mnt/unionfs-test"
    local empty_dir="/tmp/empty-dir"
    
    sudo mkdir -p "$empty_dir" "$merge_mount"
    
    # Mount the NFS share
    cleanup_mounts
    
    if ! sudo mount -t nfs "$NFS_SERVER:$NFS_EXPORT" "$TEMP_MOUNT"; then
        error "Failed to mount NFS share for unionfs test"
        result "❌ FAILED: Unionfs/mergerfs approach"
        result "  - NFS mount failed"
        result ""
        return 1
    fi
    
    # Create mergerfs mount
    log "Creating mergerfs mount"
    if sudo mergerfs -o defaults,allow_other,use_ino "$empty_dir:$TEMP_MOUNT" "$merge_mount"; then
        log "Mergerfs mount successful"
        
        # Check content
        local check_result
        local original_temp="$TEMP_MOUNT"
        TEMP_MOUNT="$merge_mount"
        check_content
        check_result=$?
        TEMP_MOUNT="$original_temp"
        
        # Record results
        if [ $check_result -eq 0 ]; then
            result "✅ SUCCESS: Unionfs/mergerfs approach"
            result "  - Command: mergerfs -o defaults,allow_other,use_ino /empty/dir:/nfs/mount /final/mount"
            result "  - All test directories visible"
            result ""
        elif [ $check_result -eq 2 ]; then
            result "⚠️ PARTIAL: Unionfs/mergerfs approach"
            result "  - Command: mergerfs -o defaults,allow_other,use_ino /empty/dir:/nfs/mount /final/mount"
            result "  - Some test directories visible"
            result ""
        else
            result "❌ FAILED: Unionfs/mergerfs approach"
            result "  - Command: mergerfs -o defaults,allow_other,use_ino /empty/dir:/nfs/mount /final/mount"
            result "  - Mount successful but no content visible"
            result ""
        fi
        
        # Cleanup
        log "Unmounting mergerfs..."
        sudo umount "$merge_mount"
    else
        error "Mergerfs mount failed"
        result "❌ FAILED: Unionfs/mergerfs approach"
        result "  - NFS mount succeeded"
        result "  - Mergerfs mount failed"
        result ""
    fi
    
    # Cleanup
    sudo umount "$TEMP_MOUNT" 2>/dev/null || true
    sudo rmdir "$empty_dir" "$merge_mount" 2>/dev/null || true
    
    return $check_result
}
