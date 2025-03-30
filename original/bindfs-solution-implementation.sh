#!/bin/bash
# Bindfs Solution Implementation
# This script implements the bindfs solution for TrueNAS Scale NFS mounts
# IMPORTANT: Only use this after testing confirms bindfs works!

set -e

# Configuration
NFS_SERVER="babka.7homas.com"
NFS_EXPORT="/mnt/data-tank/docker"
TEMP_MOUNT="/mnt/nfs-temp"
FINAL_MOUNT="/mnt/docker"
BINDFS_USER="$(id -un)"
BINDFS_GROUP="$(id -gn)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Utility functions
log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}SUCCESS: $1${NC}"; }
error() { echo -e "${RED}ERROR: $1${NC}"; exit 1; }
warning() { echo -e "${YELLOW}WARNING: $1${NC}"; }

# Install required packages
install_dependencies() {
    log "Installing required packages..."
    sudo apt-get update
    sudo apt-get install -y bindfs nfs-common
}

# Clean up existing mounts
cleanup_mounts() {
    log "Cleaning up existing mounts..."
    sudo umount -f "${FINAL_MOUNT}" 2>/dev/null || true
    sudo umount -f "${TEMP_MOUNT}" 2>/dev/null || true
    
    # Ensure mount points exist
    sudo mkdir -p "${TEMP_MOUNT}" "${FINAL_MOUNT}"
}

# Create systemd mount units
create_systemd_mounts() {
    log "Creating systemd mount units..."
    
    # Create NFS mount unit
    sudo bash -c "cat > /etc/systemd/system/mnt-nfs-temp.mount << EOF
[Unit]
Description=Mount NFS Share from TrueNAS
After=network.target

[Mount]
What=${NFS_SERVER}:${NFS_EXPORT}
Where=${TEMP_MOUNT}
Type=nfs
Options=vers=3,rw,hard,timeo=600
TimeoutSec=30

[Install]
WantedBy=multi-user.target
EOF"

    # Create bindfs mount unit
    sudo bash -c "cat > /etc/systemd/system/mnt-docker.mount << EOF
[Unit]
Description=Bindfs mount for Docker directories
After=mnt-nfs-temp.mount
Requires=mnt-nfs-temp.mount

[Mount]
What=${TEMP_MOUNT}
Where=${FINAL_MOUNT}
Type=fuse.bindfs
Options=force-user=${BINDFS_USER},force-group=${BINDFS_GROUP},create-for-user=root,create-for-group=root,chown-ignore,chmod-ignore
TimeoutSec=30

[Install]
WantedBy=multi-user.target
EOF"

    # Enable and reload systemd
    sudo systemctl daemon-reload
    sudo systemctl enable mnt-nfs-temp.mount mnt-docker.mount
}

# Test the bindfs solution
test_solution() {
    log "Testing bindfs solution..."
    
    # Mount via systemd
    sudo systemctl start mnt-nfs-temp.mount
    sleep 2
    sudo systemctl start mnt-docker.mount
    sleep 2
    
    # Verify mounts
    if ! mount | grep -q "${TEMP_MOUNT}"; then
        error "NFS mount failed. Check systemd logs with: sudo journalctl -u mnt-nfs-temp.mount"
    fi
    
    if ! mount | grep -q "${FINAL_MOUNT}"; then
        error "Bindfs mount failed. Check systemd logs with: sudo journalctl -u mnt-docker.mount"
    fi
    
    # Check content
    local test_dirs=("caddy" "actual-budget" "homer" "vaultwarden" "seafile")
    local success_count=0
    
    for dir in "${test_dirs[@]}"; do
        if [ -d "${FINAL_MOUNT}/${dir}" ]; then
            local count=$(find "${FINAL_MOUNT}/${dir}" -type f 2>/dev/null | wc -l)
            if [ "$count" -gt 0 ]; then
                success "${dir} directory shows $count files"
                success_count=$((success_count + 1))
            else
                warning "${dir} directory shows no files"
            fi
        else
            warning "${dir} directory not found"
        fi
    done
    
    if [ "$success_count" -eq "${#test_dirs[@]}" ]; then
        success "Solution is working correctly! All test directories show content."
        return 0
    elif [ "$success_count" -gt 0 ]; then
        warning "Partial success: $success_count/${#test_dirs[@]} directories show content."
        return 1
    else
        error "Solution failed: No test directories show content."
        return 2
    fi
}

# Main function
main() {
    log "Starting Bindfs Solution Implementation"
    
    install_dependencies
    cleanup_mounts
    create_systemd_mounts
    test_solution
    
    success "Bindfs solution has been successfully implemented!"
    log "Mounts will automatically connect at boot time."
    log "To manually control the mounts:"
    log " - Start: sudo systemctl start mnt-nfs-temp.mount mnt-docker.mount"
    log " - Stop: sudo systemctl stop mnt-docker.mount mnt-nfs-temp.mount"
    log " - Status: sudo systemctl status mnt-nfs-temp.mount mnt-docker.mount"
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
