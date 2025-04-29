#!/usr/bin/env nextflow

// Slurm Cluster Stress Test Pipeline
// This pipeline is designed to stress test a Slurm cluster by generating various workloads
// that test different aspects of the scheduler's capabilities and resilience.

// Parameters with defaults that can be overridden via command line
params.num_samples = 100           // Number of samples to process
params.mem_intensive = true        // Enable memory-intensive tasks
params.cpu_intensive = true        // Enable CPU-intensive tasks
params.io_intensive = true         // Enable I/O-intensive tasks
params.max_cpus = 16               // Maximum CPUs per task
params.max_memory = '32 GB'        // Maximum memory per task
params.max_time = '2h'             // Maximum time for any job
params.failure_rate = 0.05         // Introduce random failures (5% by default)
params.output_dir = 'results'      // Directory for output files
params.large_files = false         // Generate large files for I/O testing
params.file_size = '1GB'           // Size of large files to generate
params.short_jobs = 50             // Number of very short jobs (seconds)
params.medium_jobs = 30            // Number of medium jobs (minutes)
params.long_jobs = 20              // Number of long jobs (hour+)
params.dependency_chains = true    // Create dependency chains between processes
params.max_retry = 3               // Maximum retries for failed tasks

log.info """
=======================================================
SLURM CLUSTER STRESS TEST PIPELINE
=======================================================
Samples to process    : ${params.num_samples}
Memory-intensive      : ${params.mem_intensive}
CPU-intensive         : ${params.cpu_intensive}
I/O-intensive         : ${params.io_intensive}
Maximum CPUs          : ${params.max_cpus}
Maximum memory        : ${params.max_memory}
Maximum time          : ${params.max_time}
Failure rate          : ${params.failure_rate * 100}%
Short jobs            : ${params.short_jobs}
Medium jobs           : ${params.medium_jobs}
Long jobs             : ${params.long_jobs}
Dependency chains     : ${params.dependency_chains}
Maximum retries       : ${params.max_retry}
Output directory      : ${params.output_dir}
=======================================================
"""

// Create input channel with sample IDs
input_samples = Channel.of(1..params.num_samples)

// Process 1: Short CPU bursts (many quick jobs to test scheduler overhead)
process shortCpuBursts {
    tag "short_${sample_id}"
    
    errorStrategy { task.attempt <= params.max_retry ? 'retry' : 'ignore' }
    maxRetries params.max_retry
    
    // Randomly fail some tasks based on failure_rate
    script:
    def fail_randomly = Math.random() < params.failure_rate ? "exit 1" : ""
    
    input:
    val sample_id from input_samples.take(params.short_jobs)
    
    output:
    val sample_id into short_jobs_done
    
    script:
    """
    # Short CPU burst (5-15 seconds)
    duration=\$(( RANDOM % 10 + 5 ))
    echo "Running short job ${sample_id} for \$duration seconds"
    
    # Simple CPU load using bc
    for i in \$(seq 1 \$duration); do
        bc -l <<< "scale=4000; a(1)*4" > /dev/null
        sleep 0.5
    done
    
    # Introduce random failures based on rate
    ${fail_randomly}
    
    echo "Completed job ${sample_id}"
    """
}

// Process 2: Memory-intensive jobs
process memoryIntensiveJobs {
    tag "mem_${sample_id}"
    
    errorStrategy { task.attempt <= params.max_retry ? 'retry' : 'ignore' }
    maxRetries params.max_retry
    
    // Request variable memory for each task
    memory { (1 + Math.abs(new Random().nextGaussian()) * 0.5) * task.attempt * '4 GB' }
    time { '30m' * task.attempt }
    
    when:
    params.mem_intensive
    
    input:
    val sample_id from input_samples.take(params.medium_jobs)
    
    output:
    val sample_id into memory_jobs_done
    
    script:
    def fail_randomly = Math.random() < params.failure_rate ? "exit 1" : ""
    
    """
    # Memory intensive job
    echo "Running memory-intensive job ${sample_id}"
    
    # Calculate memory to use (70-90% of allocated)
    ALLOCATED_KB=\$(cat /proc/meminfo | grep MemTotal | awk '{print \$2}')
    USE_PERCENT=\$(( RANDOM % 20 + 70 ))
    USE_KB=\$(( ALLOCATED_KB * USE_PERCENT / 100 ))
    
    # Use stress-ng for memory testing if available
    if command -v stress-ng &> /dev/null; then
        # Run for 1-5 minutes
        duration=\$(( RANDOM % 240 + 60 ))
        stress-ng --vm 1 --vm-bytes \${USE_KB}K --vm-keep --timeout \$duration
    else
        # Fallback to a simple memory allocation with Python
        python3 -c "
import numpy as np
import time
import random

# Allocate large array
size_kb = int($USE_KB * 0.9)  # Leave some headroom
arr = np.ones((size_kb * 1024 // 8), dtype=np.float64)  # 8 bytes per float64

# Keep the memory allocated for some time
sleep_time = random.randint(60, 300)
print(f'Allocated {size_kb}KB of memory, holding for {sleep_time} seconds')
time.sleep(sleep_time)

# Do some operations on the array to prevent optimization
arr = arr * 1.01
sum_val = np.sum(arr)
print(f'Sum: {sum_val}')
"
    fi
    
    ${fail_randomly}
    
    echo "Completed memory job ${sample_id}"
    """
}

// Process 3: CPU-intensive long-running jobs
process cpuIntensiveJobs {
    tag "cpu_${sample_id}"
    
    errorStrategy { task.attempt <= params.max_retry ? 'retry' : 'ignore' }
    maxRetries params.max_retry
    
    // Request variable CPUs for each task
    cpus { Math.min(params.max_cpus, 1 + (sample_id % 8)) }
    time { '1h' * task.attempt }
    
    when:
    params.cpu_intensive
    
    input:
    val sample_id from input_samples.take(params.long_jobs)
    
    output:
    val sample_id into cpu_jobs_done
    
    script:
    def fail_randomly = Math.random() < params.failure_rate ? "exit 1" : ""
    def cpu_count = task.cpus
    
    """
    # CPU intensive job using all allocated CPUs
    echo "Running CPU-intensive job ${sample_id} with ${cpu_count} CPUs"
    
    # Use stress-ng for CPU testing if available
    if command -v stress-ng &> /dev/null; then
        # Run for 30-60 minutes
        duration=\$(( RANDOM % 1800 + 1800 ))
        stress-ng --cpu ${cpu_count} --cpu-method all --timeout \$duration
    else
        # Fallback to simple CPU-intensive tasks
        for cpu in \$(seq 1 ${cpu_count}); do
            # Run each in background on different CPU
            (
                # Run for 30-60 minutes (adjust factor to control duration)
                end_time=\$(( \$(date +%s) + RANDOM % 1800 + 1800 ))
                while [ \$(date +%s) -lt \$end_time ]; do
                    # Compute primes (CPU intensive)
                    for i in \$(seq 1 5000); do
                        factor \$i > /dev/null
                    done
                    # Matrix operations
                    bc -l <<< "scale=5000; a(1)*4" > /dev/null
                done
            ) &
        done
        wait
    fi
    
    ${fail_randomly}
    
    echo "Completed CPU job ${sample_id}"
    """
}

// Process 4: I/O intensive jobs
process ioIntensiveJobs {
    tag "io_${sample_id}"
    
    errorStrategy { task.attempt <= params.max_retry ? 'retry' : 'ignore' }
    maxRetries params.max_retry
    
    publishDir "${params.output_dir}/io_test", mode: 'copy', overwrite: true
    
    when:
    params.io_intensive
    
    input:
    val sample_id from input_samples.take(params.medium_jobs)
    
    output:
    file "io_test_${sample_id}.txt" optional true
    val sample_id into io_jobs_done
    
    script:
    def fail_randomly = Math.random() < params.failure_rate ? "exit 1" : ""
    def file_size = params.large_files ? params.file_size : "100MB"
    
    """
    # I/O intensive job
    echo "Running I/O-intensive job ${sample_id}"
    
    # Generate large file
    dd if=/dev/urandom of=large_file_1.bin bs=1M count=${file_size.replaceAll(/[^\d]/, "")} iflag=fullblock
    
    # Multiple read/write operations
    for i in \$(seq 1 5); do
        # Copy file back and forth
        cp large_file_1.bin large_file_2.bin
        # Read the file with different I/O patterns
        dd if=large_file_2.bin of=large_file_3.bin bs=8k
        # Random reads
        dd if=large_file_3.bin of=large_file_4.bin bs=4k skip=\$(( RANDOM % 1000 )) count=100
    done
    
    # Clean up temporary files but keep one for output
    cp large_file_1.bin io_test_${sample_id}.txt
    rm large_file_*.bin
    
    ${fail_randomly}
    
    echo "Completed I/O job ${sample_id}"
    """
}

// Process 5: Mixed resource job with dependencies (runs after previous jobs)
process mixedResourceJobs {
    tag "mixed_${sample_id}"
    
    errorStrategy { task.attempt <= params.max_retry ? 'retry' : 'ignore' }
    maxRetries params.max_retry
    
    cpus { 1 + (sample_id % 4) }
    memory { "2 GB" * task.attempt }
    time { '45m' * task.attempt }
    
    publishDir "${params.output_dir}/mixed", mode: 'copy', overwrite: true
    
    when:
    params.dependency_chains
    
    input:
    val sample_id from short_jobs_done.mix(memory_jobs_done, cpu_jobs_done, io_jobs_done).take(params.short_jobs)
    
    output:
    file "mixed_output_${sample_id}.txt"
    val sample_id into mixed_jobs_done
    
    script:
    def fail_randomly = Math.random() < (params.failure_rate / 2) ? "exit 1" : ""  // Lower failure rate for dependency jobs
    
    """
    # Mixed resource job that depends on previous jobs
    echo "Running mixed dependency job ${sample_id}"
    
    # Create some CPU load
    for i in \$(seq 1 10); do
        bc -l <<< "scale=2000; a(1)*4" > /dev/null &
    done
    
    # Allocate some memory
    python3 -c "
import numpy as np
import time
arr = np.ones((500000, 500), dtype=np.float64)
for i in range(20):
    arr = arr * 1.001
    time.sleep(1)
print('Memory computation done')
"
    
    # Do some I/O
    dd if=/dev/urandom of=temp_file.bin bs=1M count=100 iflag=fullblock
    for i in \$(seq 1 5); do
        sort -R temp_file.bin > temp_sorted.bin
        cat temp_sorted.bin > mixed_output_${sample_id}.txt
    done
    rm temp_file.bin temp_sorted.bin
    
    # Write output report
    echo "Mixed job ${sample_id} completed at \$(date)" > mixed_output_${sample_id}.txt
    echo "Dependency chain tested successfully" >> mixed_output_${sample_id}.txt
    
    ${fail_randomly}
    
    echo "Completed mixed job ${sample_id}"
    """
}

// Process 6: Final aggregation job that depends on all previous jobs
process aggregationJob {
    tag "aggregation"
    
    publishDir "${params.output_dir}", mode: 'copy', overwrite: true
    
    input:
    val all_done from mixed_jobs_done.collect()
    
    output:
    file "stress_test_report.txt"
    
    script:
    """
    # Final aggregation job
    echo "Running final aggregation"
    
    echo "=========================================" > stress_test_report.txt
    echo "SLURM CLUSTER STRESS TEST - FINAL REPORT" >> stress_test_report.txt
    echo "=========================================" >> stress_test_report.txt
    echo "Report generated at: \$(date)" >> stress_test_report.txt
    echo "" >> stress_test_report.txt
    
    echo "Test Parameters:" >> stress_test_report.txt
    echo "- Samples: ${params.num_samples}" >> stress_test_report.txt
    echo "- Memory-intensive: ${params.mem_intensive}" >> stress_test_report.txt
    echo "- CPU-intensive: ${params.cpu_intensive}" >> stress_test_report.txt
    echo "- I/O-intensive: ${params.io_intensive}" >> stress_test_report.txt
    echo "- Dependency chains: ${params.dependency_chains}" >> stress_test_report.txt
    echo "- Max CPUs: ${params.max_cpus}" >> stress_test_report.txt
    echo "- Max memory: ${params.max_memory}" >> stress_test_report.txt
    echo "- Failure rate: ${params.failure_rate * 100}%" >> stress_test_report.txt
    echo "" >> stress_test_report.txt
    
    echo "Jobs completed:" >> stress_test_report.txt
    echo "- Short jobs: \$(ls -la ${params.output_dir}/mixed/mixed_output_*.txt | wc -l)" >> stress_test_report.txt
    echo "" >> stress_test_report.txt
    
    echo "Stress test completed successfully!" >> stress_test_report.txt
    
    echo "Completed aggregation job"
    """
}

workflow.onComplete {
    log.info "========================================="
    log.info "Pipeline completed at: ${workflow.complete}"
    log.info "Execution status: ${workflow.success ? 'SUCCESS' : 'FAILED'}"
    log.info "Execution duration: ${workflow.duration}"
    log.info "Command line: ${workflow.commandLine}"
    if (!workflow.success) {
        log.info "Pipeline execution failed"
    }
    log.info "========================================="
}
