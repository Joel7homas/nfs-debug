# Babka-Pita NFS Troubleshooting Framework

## Overview

This framework provides a comprehensive testing suite for troubleshooting NFS mount issues between TrueNAS Scale (babka) and Ubuntu (pita) systems. It implements the Minimalist Multi-Module Pattern to avoid context window and character limit issues during development.

## Key Features

- **Server-side testing**: Tests various NFS export configurations on TrueNAS Scale
- **Client-side testing**: Tests different NFS mount options on Ubuntu
- **Alternative solutions**: Tests bindfs and SMB/CIFS as alternatives to direct NFS mounting
- **Comprehensive reporting**: Generates detailed reports with recommendations
- **Modular design**: Minimalist Multi-Module Pattern for maintainability
- **Remote execution**: Controls both server and client from a single test controller

## Prerequisites

- TrueNAS Scale (babka) with SSH access
- Ubuntu system (pita) with SSH access
- SSH key-based authentication between babka and pita
- User "joel" on pita with sudo privileges
- Original NFS testing scripts in the `original/` directory

### Required Packages

On babka (TrueNAS Scale):
- jq
- ssh/scp

On pita (Ubuntu):
- nfs-common
- bindfs (will be installed automatically if needed)
- cifs-utils (will be installed automatically if needed)

## Directory Structure

```
babka-nfs-tester/
├── babka-tester.sh            # Main controller script
├── setup.sh                   # Setup script
├── lib/                       # Library modules
│   ├── utils-core.sh          # Core utility functions
│   ├── utils-ssh.sh           # SSH execution utilities
│   ├── utils-backup.sh        # Backup and restore utilities
│   ├── server-config-core.sh  # Core server configuration functions
│   ├── server-config-nfs.sh   # NFS-specific server configurations
│   ├── client-mount-core.sh   # Core client mount functions
│   ├── client-mount-nfs.sh    # NFS-specific client mount options
│   ├── alt-bindfs.sh          # Bindfs solution testing
│   ├── alt-smb.sh             # SMB alternative testing
│   ├── report-core.sh         # Core reporting functions
├── patches/                   # Patch scripts for original code
│   ├── patch-mount.sh         # Patches for mount commands
│   ├── patch-content.sh       # Patches for content checking
├── original/                  # Original NFS testing scripts
├── patched/                   # Patched versions of original scripts
├── results/                   # Test results and reports
└── backups/                   # Configuration backups
```

## Installation

1. Clone or download this repository to your TrueNAS Scale system (babka)
2. Copy the original NFS testing scripts to the `original/` directory
3. Run the setup script:

```bash
chmod +x setup.sh
./setup.sh
```

4. Follow the prompts to configure the framework

## Usage

Run the main testing script:

```bash
./babka-tester.sh
```

The script will:
1. Initialize the testing environment
2. Patch the original scripts to run from babka
3. Test various NFS server configurations
4. Test different NFS client mount options
5. Test bindfs and SMB alternatives
6. Generate a comprehensive report with recommendations
7. Clean up temporary changes

## Test Directories

The framework tests the following directories by default:
- caddy
- actual-budget
- homer
- vaultwarden
- seafile

You can modify these in the `babka-tester.sh` script.

## Test Report

After testing is complete, a comprehensive Markdown report will be generated in the `results/` directory. The report includes:

- Environment information
- Test summary statistics
- Detailed results for each test category
- Specific recommendations based on test results
- Implementation instructions for the most successful approaches

## Minimalist Multi-Module Pattern

This framework implements the Minimalist Multi-Module Pattern with the following constraints:

- Each module has no more than 10 functions
- Each function is limited to 25 lines of code
- Simple flat file data structures for status tracking
- Clear interfaces between modules
- Functionality split across multiple focused files

This pattern helps avoid context window limitations during development while maintaining code readability and maintainability.

## Troubleshooting

### Common Issues

- **SSH connection failures**: Ensure SSH key-based authentication is set up between babka and pita
- **Missing dependencies**: Run the setup script to check for required dependencies
- **Permission issues**: Ensure the user has sudo privileges on both systems
- **Script execution errors**: Make sure all scripts have execute permissions

### Logs

Detailed logs are saved in the `results/` directory.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Original NFS testing scripts by Joel Thomas
- Flannel-Registrar project team
- TrueNAS and Ubuntu communities
