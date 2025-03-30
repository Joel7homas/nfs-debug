# Quick Start Guide

This guide provides minimal steps to get up and running with the ZFS Nested Dataset Visibility Test Framework.

## Prerequisites

Ensure you have:
1. SSH access from babka (TrueNAS Scale) to pita (Ubuntu)
2. Passwordless sudo for the user on pita
3. At least 500MB free space on your ZFS pool

## Setup

1. **Copy scripts to babka**

   Copy all `.sh` files to a directory on babka, e.g., `/root/zfs-tests/`.

2. **Make scripts executable**

   ```bash
   chmod +x *.sh
   ```

3. **Verify SSH connectivity**

   ```bash
   # Replace 'joel' with your username on pita
   ssh joel@pita "echo 'SSH connection successful'"
   ```

4. **Verify sudo access on pita**

   ```bash
   ssh joel@pita "sudo -n echo 'Sudo access verified'" 
   ```

## Running Tests

### Basic Test Run

```bash
./nested-dataset-test.sh
```

This will:
- Create test datasets under `data-tank/docker/test-parent`
- Test NFS and SMB visibility with different configurations
- Generate a report in the `results` directory

### Run Specific Test Groups

```bash
# Test only the nested dataset hypothesis (faster)
./nested-dataset-test.sh hypothesis

# Test only ZFS property effects
./nested-dataset-test.sh properties

# Test only real-world datasets
./nested-dataset-test.sh real
```

## Viewing Results

After tests complete, check:

1. **Summary report**:
   ```bash
   cat results/nested_dataset_report.md
   ```

2. **Successful configurations**:
   ```bash
   cat results/successful_configurations.md
   ```

3. **Detailed logs**:
   ```bash
   cat results/nested-dataset-test.log
   ```

## Recommended Workflow

For best results, follow this workflow:

1. Run the hypothesis test first:
   ```bash
   ./nested-dataset-test.sh hypothesis
   ```

2. If nested datasets are confirmed as an issue, run the property tests:
   ```bash
   ./nested-dataset-test.sh properties
   ```

3. Finally, run the real dataset tests:
   ```bash
   ./nested-dataset-test.sh real
   ```

4. Review the final report:
   ```bash
   cat results/nested_dataset_report.md
   ```

## Cleaning Up

All test datasets and exports are automatically cleaned up after testing. However, if a test is interrupted, you may need to manually clean up:

```bash
# Delete test datasets
zfs destroy -r data-tank/docker/test-parent

# Clean up any leftover NFS exports
# Review the exports first
midclt call sharing.nfs.query | grep test-parent
# Then delete any exports related to test-parent
```

## Troubleshooting

If tests fail:

1. Check SSH connectivity to pita
2. Ensure the user on pita has passwordless sudo
3. Verify remote mount points are available
4. Check detailed logs for specific errors
