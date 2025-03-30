#!/bin/bash
# NFS Solutions Tester - Run on pita (Ubuntu client)
# This script systematically tests multiple NFS mount solutions
# for TrueNAS Scale to Ubuntu connectivity issues

set -e # Exit on error

# Configuration
NFS_SERVER="babka.7homas.com"
NFS_EXPORT="/mnt/data-tank/docker"
TEMP_MOUNT="/mnt/nfs-test"
TEST_DIRS=("caddy" "actual-budget" "homer" "vaultwarden" "seafile")
LOG_FILE="nfs-solutions-test-$(date +%Y%m%d-%H%M%S).log"
RESULTS_FILE="nfs-solutions-results-$(date +%Y%m%d-%H%M%S).txt"

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}SUCCESS: $1${NC}" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}ERROR: $1${NC}" | tee -a "$LOG_FILE"; }
warning() { echo -e "${YELLOW}WARNING: $1${NC}" | tee -a "$LOG_FILE"; }
header() { echo -e "\n${GREEN}=== $1 ===${NC}" | tee -a "$LOG_FILE"; }
result() { echo "$1" >> "$RESULTS_FILE"; }

# Initialize results file
initialize_results() {
    echo "NFS Solutions Test Results - $(date)" > "$RESULTS_FILE"
    echo "====================================" >> "$RESULTS_FILE"
    echo "" >> "$RESULTS_FILE"
    echo "System Information:" >> "$RESULTS_FILE"
    echo "- Client: $(hostname) - $(lsb_release -ds)" >> "$RESULTS_FILE"
    echo "- Kernel: $(uname -r)" >> "$RESULTS_FILE" 
    echo "- NFS packages: $(dpkg-query -W -f='${Version}\n' nfs-common) (nfs-common)" >> "$RESULTS_FILE"
    echo "" >> "$RESULTS_FILE"
    echo "Test Summary:" >> "$RESULTS_FILE"
    echo "--------------------------------" >> "$RESULTS_FILE"
}

# Check dependencies
check_dependencies() {
    header "Checking dependencies"
    
    local missing_deps=0
    local needs_bindfs=0
    
    log "Checking for required packages..."
    
    if ! command -v mount.nfs &> /dev/null; then
        error "NFS client not installed. Please install nfs-common package."
        missing_deps=1
    fi
    
    if ! command -v bindfs &> /dev/null; then
        warning "bindfs not installed. Will be installed for bindfs tests."
        needs_bindfs=1
    fi
    
    if [ $missing_deps -eq 1 ]; then
        error "Missing required dependencies. Please install them and try again."
        exit 1
    fi
    
    if [ $needs_bindfs -eq 1 ]; then
        log "Installing bindfs package..."
        sudo apt-get update -qq
        sudo apt-get install -y bindfs
    fi
    
    log "All dependencies satisfied."
}

# Clean up mounts
cleanup_mounts() {
    log "Cleaning up existing mounts..."
    
    # Unmount if already mounted
    sudo umount -f "${TEMP_MOUNT}" 2>/dev/null || true
    
    # Create mount point if it doesn't exist
    if [ ! -d "${TEMP_MOUNT}" ]; then
        sudo mkdir -p "${TEMP_MOUNT}"
        log "Created mount point: ${TEMP_MOUNT}"
    fi
}

# Check content visibility in test directories
check_content() {
    local all_success=true
    local total_files=0
    local visible_dirs=0
    
    for dir in "${TEST_DIRS[@]}"; do
        if [ -d "${TEMP_MOUNT}/${dir}" ]; then
            local count=$(find "${TEMP_MOUNT}/${dir}" -type f 2>/dev/null | wc -l)
            total_files=$((total_files + count))
            
            if [ "$count" -gt 0 ]; then
                success "${dir} directory shows $count files"
                visible_dirs=$((visible_dirs + 1))
                
                # Get a sample directory listing (first 5 items)
                log "Sample of ${dir} contents:"
                ls -la "${TEMP_MOUNT}/${dir}" | head -n 5 | tee -a "$LOG_FILE"
                log "..."
            else
                error "${dir} directory shows no files"
                ls -la "${TEMP_MOUNT}/${dir}" | tee -a "$LOG_FILE"
                all_success=false
            fi
        else
            warning "${dir} directory not found at ${TEMP_MOUNT}/${dir}"
            all_success=false
        fi
    done
    
    if $all_success; then
        success "All test directories show content"
        return 0
    else
        if [ "$visible_dirs" -gt 0 ]; then
            warning "Partial success: $visible_dirs/${#TEST_DIRS[@]} directories visible, $total_files total files"
            return 2
        else
            error "No test directories show content"
            return 1
        fi
    fi
}

# Test a specific NFS mount option
test_nfs_mount() {
    local description="$1"
    local options="$2"
    local nfs_version="$3"
    
    header "Testing $description"
    log "Mount command: mount -t nfs$nfs_version -o $options $NFS_SERVER:$NFS_EXPORT $TEMP_MOUNT"
    
    # Ensure we start clean
    cleanup_mounts
    
    # Try to mount with the specified options
    if sudo mount -t "nfs$nfs_version" -o "$options" "$NFS_SERVER:$NFS_EXPORT" "$TEMP_MOUNT"; then
        log "Mount successful"
        
        # Get mount details
        log "Mount details:"
        mount | grep "$TEMP_MOUNT" | tee -a "$LOG_FILE"
        
        # Check content visibility
        local check_result
        check_content
        check_result=$?
        
        # Record results
        if [ $check_result -eq 0 ]; then
            result "✅ SUCCESS: $description"
            result "  - Command: mount -t nfs$nfs_version -o $options $NFS_SERVER:$NFS_EXPORT /mount/point"
            result "  - All test directories visible"
            result ""
        elif [ $check_result -eq 2 ]; then
            result "⚠️ PARTIAL: $description"
            result "  - Command: mount -t nfs$nfs_version -o $options $NFS_SERVER:$NFS_EXPORT /mount/point"
            result "  - Some test directories visible"
            result ""
        else
            result "❌ FAILED: $description"
            result "  - Command: mount -t nfs$nfs_version -o $options $NFS_SERVER:$NFS_EXPORT /mount/point"
            result "  - Mount successful but no content visible"
            result ""
        fi
        
        # Unmount
        log "Unmounting..."
        sudo umount "$TEMP_MOUNT"
        
        return $check_result
    else
        error "Mount failed with these options"
        result "❌ FAILED: $description"
        result "  - Command: mount -t nfs$nfs_version -o $options $NFS_SERVER:$NFS_EXPORT /mount/point"
        result "  - Mount command failed"
        result ""
        return 1
    fi
}

# Source the additional test functions
source ./nfs-solutions-tester-part2.sh
source ./nfs-solutions-tester-part3.sh

# Main function to run all tests
main() {
    header "Starting NFS Solutions Tester"
    log "Testing NFS mount solutions from $NFS_SERVER:$NFS_EXPORT to $TEMP_MOUNT"
    
    # Initialize
    check_dependencies
    initialize_results
    cleanup_mounts
    
    # System information
    header "System Information"
    log "Client: $(hostname) - $(lsb_release -ds)"
    log "Kernel: $(uname -r)"
    log "NFS client: $(mount.nfs -V 2>&1 | head -n 1)"
    
    # Test current mount
    header "Testing current mount configuration"
    if mount | grep -q "$TEMP_MOUNT"; then
        log "Currently mounted with:"
        mount | grep "$TEMP_MOUNT" | tee -a "$LOG_FILE"
        
        # Check if it works
        local current_check
        check_content
        current_check=$?
        
        if [ $current_check -eq 0 ]; then
            success "Current mount configuration works!"
            result "✅ SUCCESS: Current mount configuration"
            result "  - Command: $(mount | grep "$TEMP_MOUNT" | sed 's/type //' | awk '{print "mount -t "$5" "$1" "$3" -o "$6}' | sed 's/(//' | sed 's/)//')"
            result "  - All test directories visible"
            result ""
        else
            log "Current mount has issues. Continuing with tests."
        fi
        
        # Unmount for clean tests
        sudo umount "$TEMP_MOUNT"
    else
        log "No current mount. Starting tests with clean slate."
    fi
    
    # Run all the tests
    
    # Standard NFS mount options
    test_nfs_mount "NFSv3 with default options" "rw,hard" ""
    test_nfs_mount "NFSv3 with nolock" "rw,hard,nolock" ""
    test_nfs_mount "NFSv3 with actimeo=0" "rw,hard,actimeo=0" ""
    test_nfs_mount "NFSv3 with noac" "rw,hard,noac" ""
    test_nfs_mount "NFSv3 with noacl" "rw,hard,noacl" ""
    test_nfs_mount "NFSv3 with lookupcache=none" "rw,hard,lookupcache=none" ""
    test_nfs_mount "NFSv3 with rsize/wsize" "rw,hard,rsize=1048576,wsize=1048576" ""
    test_nfs_mount "NFSv3 with all caching disabled" "rw,hard,noac,actimeo=0,lookupcache=none" ""
    
    # NFSv4 options
    test_nfs_mount "NFSv4 with default options" "rw,hard" "4"
    test_nfs_mount "NFSv4 with actimeo=0" "rw,hard,actimeo=0" "4"
    test_nfs_mount "NFSv4 with noac" "rw,hard,noac" "4"
    test_nfs_mount "NFSv4 with sec=sys explicitly" "rw,hard,sec=sys" "4"
    
    # Auth options
    test_nfs_mount "NFSv3 with explicit all_squash" "rw,hard,all_squash" ""
    test_nfs_mount "NFSv3 with explicit no_root_squash" "rw,hard,no_root_squash" ""
    
    # Advanced solutions
    test_bindfs_mount "Default configuration" "rw,hard" "--no-allow-other" ""
    test_bindfs_mount "With map options" "rw,hard" "--map=$(id -u)/0:$(id -g)/0 --create-for-user=root --create-for-group=root" ""
    test_bindfs_mount "With force options" "rw,hard" "--force-user=$(id -un) --force-group=$(id -gn) --create-for-user=root --create-for-group=root" ""
    test_bindfs_mount "With chown/chmod ignore" "rw,hard" "--force-user=$(id -un) --force-group=$(id -gn) --chown-ignore --chmod-ignore" ""
    
    # Try the binding approach with different NFS versions
    test_bindfs_mount "With NFSv4" "rw,hard" "--force-user=$(id -un) --force-group=$(id -gn) --chown-ignore --chmod-ignore" "4"
    
    # Additional solutions
    test_loopback_nfs
    test_idmap_config
    test_sysctl_params
    test_unionfs
    test_autofs
    
    # Last resort: individual dir testing
    test_individual_dirs
    
    # Generate final summary
    generate_summary
    
    # Cleanup
    cleanup_mounts
    
    # Display final results location
    echo ""
    echo -e "${GREEN}All tests completed!${NC}"
    echo "Detailed log: $LOG_FILE"
    echo "Results summary: $RESULTS_FILE"
    echo ""
    echo -e "${YELLOW}Review the results file for recommended solutions.${NC}"
}

# Generate summary of most promising solutions
generate_summary() {
    header "Generating Solution Summary"
    
    # Filter out successful solutions
    log "Analyzing results for successful solutions..."
    local successful_solutions=$(grep -A 3 "^✅ SUCCESS:" "$RESULTS_FILE")
    local partial_solutions=$(grep -A 3 "^⚠️ PARTIAL:" "$RESULTS_FILE")
    
    # Add summary to results file
    echo "" >> "$RESULTS_FILE"
    echo "RECOMMENDED SOLUTIONS" >> "$RESULTS_FILE"
    echo "======================" >> "$RESULTS_FILE"
    echo "" >> "$RESULTS_FILE"
    
    if [ -n "$successful_solutions" ]; then
        echo "Fully Working Solutions:" >> "$RESULTS_FILE"
        echo "$successful_solutions" >> "$RESULTS_FILE"
        echo "" >> "$RESULTS_FILE"
    else
        echo "No fully working solutions found." >> "$RESULTS_FILE"
        echo "" >> "$RESULTS_FILE"
        
        if [ -n "$partial_solutions" ]; then
            echo "Partially Working Solutions:" >> "$RESULTS_FILE"
            echo "$partial_solutions" >> "$RESULTS_FILE"
            echo "" >> "$RESULTS_FILE"
        fi
    fi
    
    # Make recommendations based on what worked best
    echo "IMPLEMENTATION RECOMMENDATIONS" >> "$RESULTS_FILE"
    echo "=============================" >> "$RESULTS_FILE"
    echo "" >> "$RESULTS_FILE"
    
    if grep -q "✅ SUCCESS: Bindfs" "$RESULTS_FILE"; then
        echo "RECOMMENDED APPROACH: Bindfs Solution" >> "$RESULTS_FILE"
        echo "This solution consistently works with TrueNAS Scale NFS permission issues:" >> "$RESULTS_FILE"
        echo "1. Mount NFS share to a temporary location" >> "$RESULTS_FILE"
        echo "2. Use bindfs to create a second mount with corrected permissions" >> "$RESULTS_FILE"
        echo "3. Setup can be automated with systemd mount units" >> "$RESULTS_FILE"
        echo "" >> "$RESULTS_FILE"
    elif grep -q "✅ SUCCESS: Loopback NFS" "$RESULTS_FILE"; then
        echo "RECOMMENDED APPROACH: Loopback NFS Export" >> "$RESULTS_FILE"
        echo "This solution re-exports the NFS share locally, which fixes the permission issues:" >> "$RESULTS_FILE"
        echo "1. Mount the original NFS share to a temporary location" >> "$RESULTS_FILE"
        echo "2. Export it via local NFS server" >> "$RESULTS_FILE"
        echo "3. Mount the local export to the final location" >> "$RESULTS_FILE"
        echo "" >> "$RESULTS_FILE"
    elif grep -q "✅ SUCCESS: NFSv" "$RESULTS_FILE"; then
        echo "RECOMMENDED APPROACH: Direct NFS Mount with Special Options" >> "$RESULTS_FILE"
        echo "These mount options worked directly with TrueNAS Scale:" >> "$RESULTS_FILE"
        echo "$(grep -A 2 '✅ SUCCESS: NFSv' $RESULTS_FILE | grep 'Command:')" >> "$RESULTS_FILE"
        echo "" >> "$RESULTS_FILE"
    elif grep -q "✅ SUCCESS: Individual directory mounts" "$RESULTS_FILE"; then
        echo "FALL-BACK APPROACH: Individual Directory Mounts" >> "$RESULTS_FILE"
        echo "While not ideal for scalability, each directory can be mounted individually:" >> "$RESULTS_FILE"
        echo "1. Create separate mount points for each container directory" >> "$RESULTS_FILE"
        echo "2. Mount each directory individually with standard options" >> "$RESULTS_FILE"
        echo "3. This could be automated with a script or multiple systemd mount units" >> "$RESULTS_FILE"
        echo "" >> "$RESULTS_FILE"
    else
        echo "RECOMMENDATION: Use bindfs Solution" >> "$RESULTS_FILE"
        echo "Based on extensive experience with TrueNAS Scale, the bindfs solution is most likely to work:" >> "$RESULTS_FILE"
        echo "1. Mount NFS to temp: mount -t nfs babka.7homas.com:/mnt/data-tank/docker /mnt/nfs-temp" >> "$RESULTS_FILE"
        echo "2. Bindfs to final: bindfs --force-user=$(id -un) --force-group=$(id -gn) --chown-ignore --chmod-ignore /mnt/nfs-temp /mnt/docker" >> "$RESULTS_FILE"
        echo "3. Set up with systemd mount units for persistence" >> "$RESULTS_FILE"
        echo "" >> "$RESULTS_FILE"
    fi
    
    echo "ADDITIONAL NOTES" >> "$RESULTS_FILE"
    echo "===============" >> "$RESULTS_FILE"
    echo "• Bindfs is generally the most reliable solution for TrueNAS Scale NFS permissions issues" >> "$RESULTS_FILE"
    echo "• If individual directories work but the parent directory doesn't, using bindfs will likely fix this" >> "$RESULTS_FILE"
    echo "• Any solution should be thoroughly tested before implementing in production" >> "$RESULTS_FILE"
    echo "• Consider implementing with systemd mount units for proper dependency handling" >> "$RESULTS_FILE"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
