#!/bin/bash

# Weka Filesystem I/O Benchmark Test
# This script performs intensive I/O operations to benchmark a Weka filesystem within ~5 minutes

export PATH=/nesi/nobackup/nesi99999/dsen018-test/fio:$PATH
export PATH=/nesi/nobackup/nesi99999/dsen018-test/sysstat:$PATH
export LD_LIBRARY_PATH=/nesi/nobackup/nesi99999/dsen018-test/libaio/src:$LD_LIBRARY_PATH

# =============================================
# Configuration
# =============================================
TEST_DIR="/nesi/nobackup/nesi99999/dsen018-test"  # Change this to your Weka mount point
FILE_SIZE=2G                   # Size of test files
BLOCK_SIZES=("4k" "64k" "1M")  # Block sizes to test
THREADS=(1 4 16)               # Number of parallel threads to test
TEST_DURATION=30               # Duration in seconds for each test
CLEANUP=true                   # Set to false if you want to keep test files

# Generate a unique summary file name based on the test directory
SUMMARY_FILE="weka_benchmark_summary_$(echo $TEST_DIR | tr '/' '_')_$(date +%Y%m%d_%H%M%S).txt"
RESULTS_FILE="weka_benchmark_details_$(echo $TEST_DIR | tr '/' '_')_$(date +%Y%m%d_%H%M%S).txt"

# Array to store results for summary
declare -A RESULTS

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
    
    # Store basic filesystem info
    RESULTS["fs_type"]=$(df -T $TEST_DIR | tail -1 | awk '{print $2}')
    RESULTS["fs_size"]=$(df -h $TEST_DIR | tail -1 | awk '{print $2}')
    RESULTS["fs_used"]=$(df -h $TEST_DIR | tail -1 | awk '{print $3}')
    RESULTS["fs_avail"]=$(df -h $TEST_DIR | tail -1 | awk '{print $4}')
    RESULTS["fs_use_percent"]=$(df -h $TEST_DIR | tail -1 | awk '{print $5}')

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

# Parse FIO output and store results
parse_fio_results() {
    local test_type=$1
    local block_size=$2
    local threads=$3
    local fio_output=$4
    
    # Parse bandwidth
    if [[ $fio_output =~ READ:.*bw=([0-9.]+)(.*)/s ]]; then
        value="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[2]}"
        RESULTS["${test_type}_read_bw_${block_size}_${threads}"]="${value}${unit}/s"
    fi
    
    if [[ $fio_output =~ WRITE:.*bw=([0-9.]+)(.*)/s ]]; then
        value="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[2]}"
        RESULTS["${test_type}_write_bw_${block_size}_${threads}"]="${value}${unit}/s"
    fi
    
    # Parse IOPS
    if [[ $fio_output =~ READ:.*IOPS=([0-9.]+) ]]; then
        RESULTS["${test_type}_read_iops_${block_size}_${threads}"]="${BASH_REMATCH[1]}"
    fi
    
    if [[ $fio_output =~ WRITE:.*IOPS=([0-9.]+) ]]; then
        RESULTS["${test_type}_write_iops_${block_size}_${threads}"]="${BASH_REMATCH[1]}"
    fi
    
    # Parse latency
    if [[ $fio_output =~ READ:.*avg=([0-9.]+) ]]; then
        RESULTS["${test_type}_read_lat_${block_size}_${threads}"]="${BASH_REMATCH[1]}μs"
    fi
    
    if [[ $fio_output =~ WRITE:.*avg=([0-9.]+) ]]; then
        RESULTS["${test_type}_write_lat_${block_size}_${threads}"]="${BASH_REMATCH[1]}μs"
    fi
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
            output=$(fio --name=seqwrite --directory=$TEST_DIR/weka_benchmark --ioengine=posixaio \
                --rw=write --bs=$bs --direct=1 --size=$FILE_SIZE --numjobs=$threads \
                --time_based --runtime=$TEST_DURATION --group_reporting --iodepth=64)
            echo "$output"
            
            # Parse and store results
            parse_fio_results "seqwrite" "$bs" "$threads" "$output"
            
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
            output=$(fio --name=seqread --directory=$TEST_DIR/weka_benchmark --ioengine=posixaio \
                --rw=read --bs=$bs --direct=1 --size=$FILE_SIZE --numjobs=$threads \
                --time_based --runtime=$TEST_DURATION --group_reporting --iodepth=64)
            echo "$output"
            
            # Parse and store results
            parse_fio_results "seqread" "$bs" "$threads" "$output"
            
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
            output=$(fio --name=randrw --directory=$TEST_DIR/weka_benchmark --ioengine=posixaio \
                --rw=randrw --rwmixread=70 --bs=$bs --direct=1 \
                --size=$FILE_SIZE --numjobs=$threads --time_based \
                --runtime=$TEST_DURATION --group_reporting --iodepth=64)
            echo "$output"
            
            # Parse and store results
            parse_fio_results "randrw" "$bs" "$threads" "$output"
            
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
        time_output=$(time -p (
            for j in {1..1000}; do
                touch "$TEST_DIR/weka_benchmark/smallfile_$i_$j"
            done
        ) 2>&1)
        echo "$time_output"
        
        # Extract real time
        if [[ $time_output =~ real\ ([0-9.]+) ]]; then
            RESULTS["metadata_create_${i}"]="${BASH_REMATCH[1]}s"
        fi
    done
    
    echo -e "\nListing files (metadata read benchmark)"
    time_output=$(time -p find "$TEST_DIR/weka_benchmark" -type f | wc -l 2>&1)
    echo "$time_output"
    
    # Extract real time
    if [[ $time_output =~ real\ ([0-9.]+) ]]; then
        RESULTS["metadata_list"]="${BASH_REMATCH[1]}s"
    fi
    
    echo -e "\nRemoving files (deletion benchmark)"
    time_output=$(time -p rm -f "$TEST_DIR/weka_benchmark"/smallfile_* 2>&1)
    echo "$time_output"
    
    # Extract real time
    if [[ $time_output =~ real\ ([0-9.]+) ]]; then
        RESULTS["metadata_delete"]="${BASH_REMATCH[1]}s"
    fi
}

# Test 5: Concurrent File Access
test_concurrent_access() {
    print_header "TEST 5: Concurrent File Access"
    
    # Create shared test file
    dd if=/dev/urandom of=$TEST_DIR/weka_benchmark/shared_file bs=1M count=1024 conv=fsync
    
    echo "Testing concurrent access with 16 processes, mixed read/write"
    output=$(fio --name=concurrent --filename=$TEST_DIR/weka_benchmark/shared_file \
        --ioengine=posixaio --rw=randrw --rwmixread=50 --bs=64k \
        --direct=1 --numjobs=16 --time_based --runtime=$TEST_DURATION \
        --group_reporting --iodepth=16)
    echo "$output"
    
    # Parse and store results
    parse_fio_results "concurrent" "64k" "16" "$output"
}

# Test 6: I/O Streaming Test (similar to real-world data streaming)
test_streaming() {
    print_header "TEST 6: I/O Streaming Test"
    
    echo "Testing streaming write performance (simulates data ingest)"
    output=$(fio --name=stream_write --directory=$TEST_DIR/weka_benchmark --ioengine=posixaio \
        --rw=write --bs=1M --direct=1 --size=$FILE_SIZE --numjobs=4 \
        --time_based --runtime=$TEST_DURATION --group_reporting --iodepth=16 \
        --rate_process=poisson --rate=50m)
    echo "$output"
    
    # Parse and store results
    parse_fio_results "stream" "write" "4" "$output"
    
    echo -e "\nTesting streaming read performance (simulates data processing)"
    output=$(fio --name=stream_read --directory=$TEST_DIR/weka_benchmark --ioengine=posixaio \
        --rw=read --bs=1M --direct=1 --size=$FILE_SIZE --numjobs=4 \
        --time_based --runtime=$TEST_DURATION --group_reporting --iodepth=16 \
        --rate_process=poisson --rate=50m)
    echo "$output"
    
    # Parse and store results
    parse_fio_results "stream" "read" "4" "$output"
}

# Create summary report
generate_summary() {
    print_header "PERFORMANCE SUMMARY REPORT"
    
    # Create summary report file
    {
        echo "==============================================="
        echo "  WEKA FILESYSTEM I/O BENCHMARK SUMMARY"
        echo "==============================================="
        echo
        echo "TEST LOCATION: $TEST_DIR"
        echo "TEST DATE: $(date)"
        echo "TEST SYSTEM: $(hostname)"
        echo
        echo "FILESYSTEM INFO:"
        echo "  Type: ${RESULTS["fs_type"]}"
        echo "  Size: ${RESULTS["fs_size"]}"
        echo "  Used: ${RESULTS["fs_used"]} (${RESULTS["fs_use_percent"]})"
        echo "  Available: ${RESULTS["fs_avail"]}"
        echo
        echo "==============================================="
        echo "SEQUENTIAL WRITE PERFORMANCE:"
        echo "==============================================="
        echo "Block Size | Threads |   Bandwidth   |    IOPS    | Latency"
        echo "-----------+---------+--------------+------------+----------"
        for bs in "${BLOCK_SIZES[@]}"; do
            for threads in "${THREADS[@]}"; do
                printf "%-10s | %-7s | %-12s | %-10s | %-s\n" \
                    "$bs" "$threads" \
                    "${RESULTS["seqwrite_write_bw_${bs}_${threads}"]:-N/A}" \
                    "${RESULTS["seqwrite_write_iops_${bs}_${threads}"]:-N/A}" \
                    "${RESULTS["seqwrite_write_lat_${bs}_${threads}"]:-N/A}"
            done
        done
        echo
        echo "==============================================="
        echo "SEQUENTIAL READ PERFORMANCE:"
        echo "==============================================="
        echo "Block Size | Threads |   Bandwidth   |    IOPS    | Latency"
        echo "-----------+---------+--------------+------------+----------"
        for bs in "${BLOCK_SIZES[@]}"; do
            for threads in "${THREADS[@]}"; do
                printf "%-10s | %-7s | %-12s | %-10s | %-s\n" \
                    "$bs" "$threads" \
                    "${RESULTS["seqread_read_bw_${bs}_${threads}"]:-N/A}" \
                    "${RESULTS["seqread_read_iops_${bs}_${threads}"]:-N/A}" \
                    "${RESULTS["seqread_read_lat_${bs}_${threads}"]:-N/A}"
            done
        done
        echo
        echo "==============================================="
        echo "RANDOM READ/WRITE MIX PERFORMANCE (70/30):"
        echo "==============================================="
        echo "Block Size | Threads | Read BW | Write BW | Read IOPS | Write IOPS"
        echo "-----------+---------+---------+----------+-----------+-----------"
        for bs in "${BLOCK_SIZES[@]}"; do
            for threads in "${THREADS[@]}"; do
                printf "%-10s | %-7s | %-7s | %-8s | %-9s | %-s\n" \
                    "$bs" "$threads" \
                    "${RESULTS["randrw_read_bw_${bs}_${threads}"]:-N/A}" \
                    "${RESULTS["randrw_write_bw_${bs}_${threads}"]:-N/A}" \
                    "${RESULTS["randrw_read_iops_${bs}_${threads}"]:-N/A}" \
                    "${RESULTS["randrw_write_iops_${bs}_${threads}"]:-N/A}"
            done
        done
        echo
        echo "==============================================="
        echo "METADATA OPERATIONS PERFORMANCE:"
        echo "==============================================="
        echo "Create 5000 files: ${RESULTS["metadata_create_1"]:-N/A} to ${RESULTS["metadata_create_5"]:-N/A}"
        echo "List all files: ${RESULTS["metadata_list"]:-N/A}"
        echo "Delete all files: ${RESULTS["metadata_delete"]:-N/A}"
        echo
        echo "==============================================="
        echo "CONCURRENT ACCESS PERFORMANCE (16 threads, 64k):"
        echo "==============================================="
        echo "Read Bandwidth: ${RESULTS["concurrent_read_bw_64k_16"]:-N/A}"
        echo "Write Bandwidth: ${RESULTS["concurrent_write_bw_64k_16"]:-N/A}"
        echo "Read IOPS: ${RESULTS["concurrent_read_iops_64k_16"]:-N/A}"
        echo "Write IOPS: ${RESULTS["concurrent_write_iops_64k_16"]:-N/A}"
        echo
        echo "==============================================="
        echo "STREAMING I/O PERFORMANCE:"
        echo "==============================================="
        echo "Write Throughput: ${RESULTS["stream_write_bw_write_4"]:-N/A}"
        echo "Read Throughput: ${RESULTS["stream_read_bw_read_4"]:-N/A}"
        echo
        echo "==============================================="
        echo "BEST PERFORMANCE VALUES:"
        echo "==============================================="
        # Find best sequential write bandwidth
        best_seq_write_bw="0"
        best_seq_write_config=""
        for bs in "${BLOCK_SIZES[@]}"; do
            for threads in "${THREADS[@]}"; do
                key="seqwrite_write_bw_${bs}_${threads}"
                if [[ -n "${RESULTS[$key]}" ]]; then
                    value=$(echo "${RESULTS[$key]}" | sed -E 's/([0-9.]+).*/\1/')
                    if (( $(echo "$value > $best_seq_write_bw" | bc -l) )); then
                        best_seq_write_bw="$value"
                        best_seq_write_config="$bs block size, $threads threads"
                    fi
                fi
            done
        done
        
        # Find best sequential read bandwidth
        best_seq_read_bw="0"
        best_seq_read_config=""
        for bs in "${BLOCK_SIZES[@]}"; do
            for threads in "${THREADS[@]}"; do
                key="seqread_read_bw_${bs}_${threads}"
                if [[ -n "${RESULTS[$key]}" ]]; then
                    value=$(echo "${RESULTS[$key]}" | sed -E 's/([0-9.]+).*/\1/')
                    if (( $(echo "$value > $best_seq_read_bw" | bc -l) )); then
                        best_seq_read_bw="$value"
                        best_seq_read_config="$bs block size, $threads threads"
                    fi
                fi
            done
        done
        
        echo "Best Sequential Write: $best_seq_write_bw MB/s ($best_seq_write_config)"
        echo "Best Sequential Read: $best_seq_read_bw MB/s ($best_seq_read_config)"
        echo
        echo "==============================================="
        echo "RECOMMENDATION:"
        echo "==============================================="
        # Simple recommendation based on results
        if (( $(echo "$best_seq_write_bw > 500" | bc -l) && $(echo "$best_seq_read_bw > 500" | bc -l) )); then
            echo "This filesystem has EXCELLENT I/O performance!"
        elif (( $(echo "$best_seq_write_bw > 200" | bc -l) && $(echo "$best_seq_read_bw > 200" | bc -l) )); then
            echo "This filesystem has GOOD I/O performance."
        else
            echo "This filesystem has MODERATE I/O performance. Consider tuning or alternative storage solutions for I/O-intensive workloads."
        fi
        echo
        echo "Report generated at $(date)"
        echo "==============================================="
    } > "$SUMMARY_FILE"
    
    echo "Summary report saved to: $SUMMARY_FILE"
    cat "$SUMMARY_FILE"
}

# =============================================
# Main Execution
# =============================================

main() {
    # Redirect all output to both terminal and results file
    exec > >(tee "$RESULTS_FILE") 2>&1
    
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
    
    # Generate detailed summary report
    generate_summary
    
    # Cleanup
    cleanup
    
    echo "Detailed results saved to: $RESULTS_FILE"
}

# Run the benchmark
main
