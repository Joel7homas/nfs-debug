#!/bin/bash
# setup.sh - Set up the NFS testing framework
# Creates directory structure and copies original scripts

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

echo "==============================================="
echo "  BABKA-PITA NFS TROUBLESHOOTING FRAMEWORK"
echo "  Setup Script"
echo "==============================================="
echo ""

# Check dependencies
log_info "Checking dependencies..."
for cmd in ssh scp jq sed grep; do
    if ! command -v $cmd &> /dev/null; then
        log_error "$cmd is required but not installed"
    fi
done

# Check for TrueNAS midclt command (TrueNAS specific)
if ! command -v midclt &> /dev/null; then
    log_warning "midclt command not found. This script should be run on TrueNAS Scale (babka)"
    read -p "Continue anyway? (y/n): " continue_setup
    if [[ "$continue_setup" != "y" && "$continue_setup" != "Y" ]]; then
        log_error "Setup aborted"
    fi
fi

# Prompt for configuration
log_info "Configuring environment..."
read -p "Remote host (default: pita): " remote_host
remote_host=${remote_host:-pita}

read -p "Remote user (default: joel): " remote_user
remote_user=${remote_user:-joel}

read -p "Export path (default: /mnt/data-tank/docker): " export_path
export_path=${export_path:-/mnt/data-tank/docker}

# Validate SSH connection
log_info "Checking SSH connectivity to ${remote_user}@${remote_host}..."
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "${remote_user}@${remote_host}" "echo 'Connection successful'" &> /dev/null; then
    log_warning "Cannot connect to ${remote_host} via SSH. Please check your SSH configuration."
    read -p "Continue anyway? (y/n): " continue_setup
    if [[ "$continue_setup" != "y" && "$continue_setup" != "Y" ]]; then
        log_error "Setup aborted"
    fi
fi

# Create directory structure
log_info "Creating directory structure..."
mkdir -p "${SCRIPT_DIR}/lib"
mkdir -p "${SCRIPT_DIR}/patches"
mkdir -p "${SCRIPT_DIR}/original"
mkdir -p "${SCRIPT_DIR}/patched"
mkdir -p "${SCRIPT_DIR}/results"
mkdir -p "${SCRIPT_DIR}/backups"

# Update configuration in babka-tester.sh if it exists
if [ -f "${SCRIPT_DIR}/babka-tester.sh" ]; then
    log_info "Updating configuration in babka-tester.sh..."
    sed -i "s/^export REMOTE_HOST=.*/export REMOTE_HOST=\"$remote_host\"/" "${SCRIPT_DIR}/babka-tester.sh"
    sed -i "s/^export REMOTE_USER=.*/export REMOTE_USER=\"$remote_user\"/" "${SCRIPT_DIR}/babka-tester.sh"
    sed -i "s|^export EXPORT_PATH=.*|export EXPORT_PATH=\"$export_path\"|" "${SCRIPT_DIR}/babka-tester.sh"
fi

# Ask user to copy original NFS testing scripts
log_info "Please copy your original NFS testing scripts to ${SCRIPT_DIR}/original/"
log_info "The following files are expected:"
log_info "  - nfs-solutions-tester-part1.sh"
log_info "  - nfs-solutions-tester-part2.sh"
log_info "  - nfs-solutions-tester-part3.sh"

read -p "Have you copied the original scripts? (y/n): " scripts_copied
if [[ "$scripts_copied" != "y" && "$scripts_copied" != "Y" ]]; then
    log_warning "Please copy the scripts before continuing"
else
    # Verify scripts exist
    missing_scripts=0
    for script in "nfs-solutions-tester-part1.sh" "nfs-solutions-tester-part2.sh" "nfs-solutions-tester-part3.sh"; do
        if [ ! -f "${SCRIPT_DIR}/original/${script}" ]; then
            log_warning "Missing script: ${script}"
            missing_scripts=1
        fi
    done
    
    if [ $missing_scripts -eq 0 ]; then
        log_success "All required scripts found"
    else
        log_warning "Some scripts are missing. Please copy them before running the framework."
    fi
fi

# Make scripts executable
log_info "Making scripts executable..."
chmod +x "${SCRIPT_DIR}/babka-tester.sh" 2>/dev/null || true
chmod +x "${SCRIPT_DIR}/lib/"*.sh 2>/dev/null || true
chmod +x "${SCRIPT_DIR}/patches/"*.sh 2>/dev/null || true
chmod +x "${SCRIPT_DIR}/original/"*.sh 2>/dev/null || true

log_success "Setup completed successfully!"
echo ""
echo "To run the NFS troubleshooting framework, execute:"
echo "  ${SCRIPT_DIR}/babka-tester.sh"
echo ""
echo "Thank you for using the Babka-Pita NFS Troubleshooting Framework!"
