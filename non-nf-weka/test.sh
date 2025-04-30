#!/bin/bash

# Weka Filesystem I/O Benchmark Test
# This script performs intensive I/O operations to benchmark a Weka filesystem within ~5 minutes

export PATH=/nesi/nobackup/nesi99999/dsen018-test/fio:$PATH
export PATH=/nesi/nobackup/nesi99999/dsen018-test/sysstat:$PATH
export LD_LIBRARY_PATH=/nesi/nobackup/nesi99999/dsen018-test/libaio/src:$LD_LIBRARY_PATH
# =============================================
# Configuration
# =============================================
TEST_DIR="/nesi/nobackup/nesi99999/dsen018-test"        # Change this to your Weka mount point
FILE_SIZE=2G                   # Size of test files
BLOCK_SIZES=("4k" "64k" "1M")  # Block sizes to test
THREADS=(1 4 16)               # Number of parallel threads to test
TEST_DURATION=30               # Duration in seconds for each test
CLEANUP=true                   # Set to false if you want to keep test files

# =============================================
# Helper Functions
# =============================================

# Print section header
print_header() {
    echo -e "\n=========================================="
    echo -e "  $1"
    echo -e "==========================================\n"
}

# Check if required tools are installed
check_requirements() {
    for cmd in fio dd sync iostat df; do
        if ! command -v $cmd &> /dev/null; then
            echo "Error: $cmd is required but not installed."
            exit 1
        fi
    done
}

# Print filesystem info
print_fs_info() {
    print_header "Filesystem Information"
    echo "Mount point: $TEST_DIR"
    echo "Filesystem details:"
    df -h $TEST_DIR
    echo

    # If weka status command exists, show cluster status
    if command -v weka &> /dev/null; then
        echo "Weka cluster status:"
        weka status
    fi
}

# Create test directory if it doesn't exist
setup_test_dir() {
    print_header "Setting up test directory"
    if [ ! -d "$TEST_DIR" ]; then
        echo "Error: Test directory $TEST_DIR does not exist!"
        exit 1
    fi
    
    echo "Creating test directory: $TEST_DIR/weka_benchmark"
    mkdir -p "$TEST_DIR/weka_benchmark"
    cd "$TEST_DIR/weka_benchmark" || exit 1
    echo "Working directory: $(pwd)"
}

# Cleanup test files
cleanup() {
    if [ "$CLEANUP" = true ]; then
        print_header "Cleaning up test files"
        echo "Removing test directory: $TEST_DIR/weka_benchmark"
        rm -rf "$TEST_DIR/weka_benchmark"
    else
        echo "Skipping cleanup, test files remain in $TEST_DIR/weka_benchmark"
    fi
}

# =============================================
# Benchmark Tests
# =============================================

# Test 1: Sequential Write Performance
test_sequential_write() {
    print_header "TEST 1: Sequential Write Performance"
    
    for bs in "${BLOCK_SIZES[@]}"; do
        for threads in "${THREADS[@]}"; do
            echo "Sequential write: $bs block size, $threads thread(s), $TEST_DURATION seconds"
            fio --name=seqwrite --directory=$TEST_DIR/weka_benchmark --ioengine=posixaio \
                --rw=write --bs=$bs --direct=1 --size=$FILE_SIZE --numjobs=$threads \
                --time_based --runtime=$TEST_DURATION --group_reporting --iodepth=64
            echo
            sync
            sleep 2
        done
    done
}

# Test 2: Sequential Read Performance
test_sequential_read() {
    print_header "TEST 2: Sequential Read Performance"
    
    # Create a file for reading
    dd if=/dev/urandom of=$TEST_DIR/weka_benchmark/readtest bs=1M count=1024 conv=fsync
    sync
    
    for bs in "${BLOCK_SIZES[@]}"; do
        for threads in "${THREADS[@]}"; do
            echo "Sequential read: $bs block size, $threads thread(s), $TEST_DURATION seconds"
            fio --name=seqread --directory=$TEST_DIR/weka_benchmark --ioengine=posixaio \
                --rw=read --bs=$bs --direct=1 --size=$FILE_SIZE --numjobs=$threads \
                --time_based --runtime=$TEST_DURATION --group_reporting --iodepth=64
            echo
            sleep 2
        done
    done
}

# Test 3: Random Read/Write Mix
test_random_rw() {
    print_header "TEST 3: Random Read/Write Mix (70/30)"
    
    for bs in "${BLOCK_SIZES[@]}"; do
        for threads in "${THREADS[@]}"; do
            echo "Random r/w mix: $bs block size, $threads thread(s), $TEST_DURATION seconds"
            fio --name=randrw --directory=$TEST_DIR/weka_benchmark --ioengine=posixaio \
                --rw=randrw --rwmixread=70 --bs=$bs --direct=1 \
                --size=$FILE_SIZE --numjobs=$threads --time_based \
                --runtime=$TEST_DURATION --group_reporting --iodepth=64
            echo
            sync
            sleep 2
        done
    done
}

# Test 4: Metadata Operations Test
test_metadata_ops() {
    print_header "TEST 4: Metadata Operations"
    
    echo "Creating many small files (file creation benchmark)"
    for i in {1..5}; do
        time (
            for j in {1..1000}; do
                touch "$TEST_DIR/weka_benchmark/smallfile_$i_$j"
            done
        )
    done
    
    echo -e "\nListing files (metadata read benchmark)"
    time find "$TEST_DIR/weka_benchmark" -type f | wc -l
    
    echo -e "\nRemoving files (deletion benchmark)"
    time rm -f "$TEST_DIR/weka_benchmark"/smallfile_*
}

# Test 5: Concurrent File Access
test_concurrent_access() {
    print_header "TEST 5: Concurrent File Access"
    
    # Create shared test file
    dd if=/dev/urandom of=$TEST_DIR/weka_benchmark/shared_file bs=1M count=1024 conv=fsync
    
    echo "Testing concurrent access with 16 processes, mixed read/write"
    fio --name=concurrent --filename=$TEST_DIR/weka_benchmark/shared_file \
        --ioengine=posixaio --rw=randrw --rwmixread=50 --bs=64k \
        --direct=1 --numjobs=16 --time_based --runtime=$TEST_DURATION \
        --group_reporting --iodepth=16
}

# Test 6: I/O Streaming Test (similar to real-world data streaming)
test_streaming() {
    print_header "TEST 6: I/O Streaming Test"
    
    echo "Testing streaming write performance (simulates data ingest)"
    fio --name=stream_write --directory=$TEST_DIR/weka_benchmark --ioengine=posixaio \
        --rw=write --bs=1M --direct=1 --size=$FILE_SIZE --numjobs=4 \
        --time_based --runtime=$TEST_DURATION --group_reporting --iodepth=16 \
        --rate_process=poisson --rate=50m
    
    echo -e "\nTesting streaming read performance (simulates data processing)"
    fio --name=stream_read --directory=$TEST_DIR/weka_benchmark --ioengine=posixaio \
        --rw=read --bs=1M --direct=1 --size=$FILE_SIZE --numjobs=4 \
        --time_based --runtime=$TEST_DURATION --group_reporting --iodepth=16 \
        --rate_process=poisson --rate=50m
}

# =============================================
# Main Execution
# =============================================

main() {
    echo "==================================================="
    echo "      WEKA FILESYSTEM I/O BENCHMARK TOOL           "
    echo "==================================================="
    echo "Starting benchmark at $(date)"
    echo
    
    # Check requirements
    check_requirements
    
    # Setup
    print_fs_info
    setup_test_dir
    
    # Get start time
    start_time=$(date +%s)
    
    # Run tests (adjust these based on your 5-minute time constraint)
    test_sequential_write
    test_sequential_read
    test_random_rw
    test_metadata_ops
    test_concurrent_access
    test_streaming
    
    # Calculate elapsed time
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))
    minutes=$((elapsed / 60))
    seconds=$((elapsed % 60))
    
    # Print summary
    print_header "BENCHMARK SUMMARY"
    echo "Benchmark completed in $minutes minutes and $seconds seconds"
    echo "Tests performed:"
    echo "  - Sequential Write Performance"
    echo "  - Sequential Read Performance"
    echo "  - Random Read/Write Mix"
    echo "  - Metadata Operations"
    echo "  - Concurrent File Access"
    echo "  - I/O Streaming Test"
    echo
    echo "Results are displayed above for each test"
    echo "Completed at $(date)"
    
    # Cleanup
    cleanup
}

# Run the benchmark
main
