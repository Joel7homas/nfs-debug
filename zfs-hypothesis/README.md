# ZFS Nested Dataset Visibility Test Framework

This framework tests the hypothesis that parent-child ZFS dataset relationships affect visibility when exporting datasets via NFS/SMB. It implements a minimalist multi-module pattern to avoid character limits and maintains compatibility with existing test harnesses.

## Overview

The framework creates test dataset structures and exports them via NFS and SMB to test visibility from a remote Ubuntu client. It also tests how various ZFS properties affect visibility.

## Requirements

- TrueNAS Scale 24.10.2 on the server (babka)
- Ubuntu on the client (pita)
- SSH access from the server to the client
- Passwordless sudo for the user on the client

## Script Structure

- `nested-dataset-test-core.sh`: Core utilities and common functions
- `dataset-management.sh`: ZFS dataset creation and management
- `export-management.sh`: NFS/SMB export management
- `visibility-testing.sh`: Testing NFS/SMB visibility
- `property-testing.sh`: Testing ZFS property effects
- `nested-dataset-test.sh`: Main test runner

## Installation

1. Copy all scripts to a directory on the TrueNAS Scale server (babka)
2. Make scripts executable:
   ```bash
   chmod +x *.sh
   ```

## Usage

### Running All Tests

```bash
./nested-dataset-test.sh
```

### Running Specific Test Groups

```bash
# Test only the nested dataset hypothesis
./nested-dataset-test.sh hypothesis

# Test only property effects
./nested-dataset-test.sh properties

# Test only real datasets
./nested-dataset-test.sh real

# Generate report from existing results
./nested-dataset-test.sh report
```

### Customizing Test Parameters

You can customize test parameters by setting environment variables:

```bash
# Example: Use a different remote host and user
REMOTE_HOST=ubuntu-machine REMOTE_USER=admin ./nested-dataset-test.sh

# Example: Use a different base dataset
BASE_DATASET=data-tank/test ./nested-dataset-test.sh
```

## Test Modules

### Nested Dataset Hypothesis Test

Tests whether child datasets are visible when exporting a parent dataset vs. exporting the child dataset directly.

### Property Tests

Tests how various ZFS properties affect visibility:
- `sharenfs` property
- `aclinherit` property
- `acltype` property

### Real Dataset Tests

Tests three real-world datasets with different complexity levels:
- Jellyfin (easy case)
- Caddy (medium case)
- Vaultwarden (hard case)

## Results and Reports

Test results are stored in the `results` directory:
- `nested_dataset_results.txt`: Raw test results
- `nested_dataset_report.md`: Analysis report
- `successful_configurations.md`: Details of successful configurations

## Interpreting Results

The framework generates a comprehensive report that includes:
- Summary of test results
- Key findings based on the results
- Recommendations for improving visibility
- Conclusion with the most effective approach

## Notes

- The framework creates temporary test datasets under the specified base dataset
- All exports created during testing are automatically cleaned up
- The scripts follow the minimalist multi-module pattern to avoid character limits
- Each module has no more than 10 functions, and each function is no more than 25 lines

## Troubleshooting

- Check the log file at `results/nested-dataset-test.log` for detailed information
- Verify SSH connectivity from babka to pita
- Ensure the user on pita has passwordless sudo access
- Make sure the remote mount points `/mnt/nfs-test` and `/mnt/smb-test` are not in use
