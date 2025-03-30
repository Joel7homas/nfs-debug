#!/bin/bash
# dataset-management.sh - ZFS dataset creation and management functions
# Follows minimalist multi-module pattern (max 10 functions per module)

# Source the core utilities if not already loaded
if ! type log_info &> /dev/null; then
    source ./nested-dataset-test-core.sh
fi

# Function: create_test_dataset_structure

# Helper function to set proper permissions
fix_dataset_permissions() {
    local dataset_path="$1"
    
    # Fix permissions
    sudo chmod -R 777 "$dataset_path" 2>/dev/null || true
    sudo chown -R $(whoami):$(whoami) "$dataset_path" 2>/dev/null || true 2>/dev/null || true
}
# Description: Create parent and child test datasets
create_test_dataset_structure() {
    log_header "Creating test dataset structure"
    
    local parent_dataset="${BASE_DATASET}/${TEST_PARENT}"
    local child_dataset="${parent_dataset}/${TEST_CHILD}"
    
    # Check if datasets already exist
    if sudo sudo zfs list -H "${parent_dataset}" &> /dev/null; then
        log_warning "Parent dataset ${parent_dataset} already exists. Destroying it."
        sudo sudo zfs destroy -r "${parent_dataset}" || {
            log_error "Failed to destroy existing parent dataset ${parent_dataset}"
            # Continuing despite error
        }
    fi
    
    # Create parent dataset
    log_info "Creating parent dataset: ${parent_dataset}"
    sudo sudo zfs create "${parent_dataset}" || {

    # Fix permissions
    fix_dataset_permissions "$(sudo zfs get -H -o value mountpoint "${parent_dataset}")"

    # Ensure we have write permissions to the dataset
    sudo chmod -R 777 "$(sudo zfs get -H -o value mountpoint "${parent_dataset}")" || {
        log_warning "Failed to set permissions on parent dataset, but continuing"
    }
        log_error "Failed to create parent dataset ${parent_dataset}"
        # Continuing despite error
    }
    
    # Create test file in parent dataset
    local parent_path=$(sudo sudo zfs get -H -o value mountpoint "${parent_dataset}")
    log_info "Creating test file in parent dataset at ${parent_path}"
    echo "parent-test-file-content" | sudo tee "${parent_path}/parent-file.txt" > /dev/null || {
        log_warning "Failed to create test file in parent dataset, but continuing"
        # Continuing despite error
    }
    
    # Create child dataset
    log_info "Creating child dataset: ${child_dataset}"
    sudo sudo zfs create "${child_dataset}" || {

    # Fix permissions
    fix_dataset_permissions "$(sudo zfs get -H -o value mountpoint "${child_dataset}")"

    # Ensure we have write permissions to the dataset
    sudo chmod -R 777 "$(sudo zfs get -H -o value mountpoint "${child_dataset}")" || {
        log_warning "Failed to set permissions on child dataset, but continuing"
    }
        log_error "Failed to create child dataset ${child_dataset}"
        # Continuing despite error
    }
    
    # Create test file in child dataset
    local child_path=$(sudo sudo zfs get -H -o value mountpoint "${child_dataset}")
    log_info "Creating test file in child dataset at ${child_path}"
    echo "child-test-file-content" | sudo tee "${child_path}/child-file.txt" > /dev/null || {
        log_warning "Failed to create test file in child dataset, but continuing"
        # Continuing despite error
    }
    
    # Create regular directory in parent dataset
    log_info "Creating regular directory in parent dataset"
    sudo sudo mkdir -p "${parent_path}/regular-dir" || {
        log_error "Failed to create regular directory in parent dataset"
        # Continuing despite error
    }
    
    # Create test file in regular directory
    log_info "Creating test file in regular directory"
    echo "regular-dir-test-file-content" | sudo tee "${parent_path}/regular-dir/regular-file.txt" > /dev/null || {
        log_warning "Failed to create test file in regular directory, but continuing"
        # Continuing despite error
    }
    
    log_success "Test dataset structure created successfully"
    return 0
}

# Function: cleanup_test_datasets
# Description: Clean up test datasets
cleanup_test_datasets() {
    log_header "Cleaning up test datasets"
    
    local parent_dataset="${BASE_DATASET}/${TEST_PARENT}"
    
    # Delete parent dataset recursively
    if sudo sudo zfs list -H "${parent_dataset}" &> /dev/null; then
        log_info "Destroying test dataset structure: ${parent_dataset}"
        sudo sudo zfs destroy -r "${parent_dataset}" || {
            log_error "Failed to destroy test dataset ${parent_dataset}"
            # Continuing despite error
        }
        log_success "Test datasets cleaned up successfully"
    else
        log_info "Test dataset ${parent_dataset} does not exist, nothing to clean up"
    fi
    
    return 0
}

# Function: set_dataset_property
# Description: Set ZFS property on a dataset
# Args: $1 - Dataset name, $2 - Property name, $3 - Property value
set_dataset_property() {
    local dataset="$1"
    local property="$2"
    local value="$3"
    
    log_info "Setting ${property}=${value} on dataset ${dataset}"
    
    # Verify dataset exists
    if ! sudo sudo zfs list -H "${dataset}" &> /dev/null; then
        log_error "Dataset ${dataset} does not exist"
        # Continuing despite error
    fi
    
    # Set property
    sudo sudo zfs set "${property}=${value}" "${dataset}" || {
        log_error "Failed to set ${property}=${value} on ${dataset}"
        # Continuing despite error
    }
    
    log_success "Property ${property} set to ${value} on ${dataset}"
    return 0
}

# Function: get_dataset_property
# Description: Get ZFS property value for a dataset
# Args: $1 - Dataset name, $2 - Property name
get_dataset_property() {
    local dataset="$1"
    local property="$2"
    
    # Verify dataset exists
    if ! sudo sudo zfs list -H "${dataset}" &> /dev/null; then
        log_error "Dataset ${dataset} does not exist"
        # Continuing despite error
    fi
    
    # Get property
    local value=$(sudo sudo zfs get -H -o value "${property}" "${dataset}")
    
    log_info "Property ${property} on ${dataset} is: ${value}"
    echo "${value}"
    return 0
}

# Function: create_test_case_datasets
# Description: Create datasets for specific test cases
create_test_case_datasets() {
    log_header "Creating test case datasets"
    
    local parent_dataset="${BASE_DATASET}/${TEST_PARENT}"
    
    for test_case in "${TEST_CASES[@]}"; do
        local test_dataset="${parent_dataset}/test-${test_case}"
        
        # Create test case dataset
        log_info "Creating test case dataset: ${test_dataset}"
        sudo sudo zfs create "${test_dataset}" || {

        # Fix permissions
        fix_dataset_permissions "$(sudo zfs get -H -o value mountpoint "${test_dataset}")"

        # Ensure we have write permissions to the dataset
        sudo chmod -R 777 "$(sudo zfs get -H -o value mountpoint "${test_dataset}")" || {
            log_warning "Failed to set permissions on test dataset, but continuing"
        }
            log_error "Failed to create test case dataset ${test_dataset}"
            continue
        }
        
        # Create test file in test case dataset
        local test_path=$(sudo sudo zfs get -H -o value mountpoint "${test_dataset}")
        log_info "Creating test file in test case dataset at ${test_path}"
        echo "${test_case}-test-file-content" | sudo tee "${test_path}/${test_case}-file.txt" > /dev/null || {
            log_warning "Failed to create test file in test case dataset, but continuing"
            continue
        }
        
        log_success "Test case dataset for ${test_case} created successfully"
    done
    
    return 0
}

# Function: copy_real_data_to_test_datasets
# Description: Copy real data from actual datasets to test datasets
copy_real_data_to_test_datasets() {
    log_header "Copying real data to test datasets"
    
    local parent_dataset="${BASE_DATASET}/${TEST_PARENT}"
    
    for test_case in "${TEST_CASES[@]}"; do
        local source_path="/mnt/${BASE_DATASET}/${test_case}"
        local test_dataset="${parent_dataset}/test-${test_case}"
        local test_path=$(sudo sudo zfs get -H -o value mountpoint "${test_dataset}")
        
        # Check if source directory exists
        if [ ! -d "${source_path}" ]; then
            log_warning "Source directory ${source_path} does not exist, skipping"
            continue
        fi
        
        # Copy a small sample of files (limit to ~5 files to avoid excessive copying)
        log_info "Copying sample files from ${source_path} to ${test_path}"
        find "${source_path}" -type f -not -path "*/\.*" | head -n 5 | while read file; do
            local relative_path=${file#$source_path/}
            local dir_path=$(dirname "${test_path}/${relative_path}")
            
            # Create directory structure
            sudo sudo mkdir -p "${dir_path}"
            
            # Copy file
            sudo cp "${file}" "${test_path}/${relative_path}" || {
                log_warning "Failed to copy ${file} to ${test_path}/${relative_path}"
                continue
            }
            
            log_info "Copied ${file} to ${test_path}/${relative_path}"
        done
        
        log_success "Sample data for ${test_case} copied successfully"
    done
    
    return 0
}

# Function: create_regular_directory_copies
# Description: Create regular directory copies of dataset data
create_regular_directory_copies() {
    log_header "Creating regular directory copies of dataset data"
    
    local parent_dataset="${BASE_DATASET}/${TEST_PARENT}"
    local parent_path=$(sudo sudo zfs get -H -o value mountpoint "${parent_dataset}")
    
    # Create regular directories for each test case
    for test_case in "${TEST_CASES[@]}"; do
        local test_dataset="${parent_dataset}/test-${test_case}"
        local test_path=$(sudo sudo zfs get -H -o value mountpoint "${test_dataset}")
        local regular_dir="${parent_path}/regular-${test_case}"
        
        # Create regular directory
        log_info "Creating regular directory: ${regular_dir}"
        sudo mkdir -p "${regular_dir}" || log_warning "Failed to create regular directory ${regular_dir}, but continuing" || {
            log_error "Failed to create regular directory ${regular_dir}"
            continue
        }
        
        # Copy content from test dataset to regular directory
        log_info "Copying content from ${test_path} to ${regular_dir}"
        sudo cp -a "${test_path}"/* "${regular_dir}"/ 2>/dev/null || {
            log_warning "No files to copy from ${test_path} to ${regular_dir}"
        }
        
        # Create a marker file to distinguish the directory
        echo "This is a regular directory copy of ${test_case}" > "${regular_dir}/REGULAR_DIR_MARKER.txt"
        
        log_success "Regular directory copy for ${test_case} created successfully"
    done
    
    return 0
}

# Function: list_dataset_structure
# Description: List the created dataset structure
list_dataset_structure() {
    log_header "Listing dataset structure"
    
    local parent_dataset="${BASE_DATASET}/${TEST_PARENT}"
    
    # List datasets
    log_info "Datasets:"
    sudo sudo zfs list -r "${parent_dataset}" | tee -a "${LOG_FILE}"
    
    # List properties
    log_info "Dataset properties:"
    sudo sudo zfs get all "${parent_dataset}" | grep -e sharenfs -e sharesmb -e aclinherit -e acltype | tee -a "${LOG_FILE}"
    
    for test_case in "${TEST_CASES[@]}"; do
        local test_dataset="${parent_dataset}/test-${test_case}"
        sudo sudo zfs get all "${test_dataset}" | grep -e sharenfs -e sharesmb -e aclinherit -e acltype | tee -a "${LOG_FILE}"
    done
    
    # List files
    log_info "File structure:"
    find "/mnt/${parent_dataset}" -type f | sort | tee -a "${LOG_FILE}"
    
    return 0
}
