#!/usr/bin/env nextflow

// Simple Slurm Cluster Stress Test Pipeline
// A streamlined version that focuses on basic job types that work reliably

// Parameters with defaults
params.job_count = 50          // Number of jobs to submit
params.output_dir = 'results'  // Directory for output files
params.max_cpus = 4            // Maximum CPUs per task
params.max_memory = '4 GB'     // Maximum memory per task

log.info """
=======================================================
SIMPLE SLURM CLUSTER STRESS TEST
=======================================================
Jobs to submit        : ${params.job_count}
Maximum CPUs          : ${params.max_cpus}
Maximum memory        : ${params.max_memory}
Output directory      : ${params.output_dir}
=======================================================
"""

// Create input channels
short_jobs = Channel.of(1..params.job_count)

// Process 1: Simple CPU jobs - these are reliable and work well
process simpleCpuJobs {
    tag "cpu_${job_id}"
    
    publishDir "${params.output_dir}/cpu_jobs", mode: 'copy', overwrite: true
    
    input:
    val job_id from short_jobs
    
    output:
    file "cpu_job_${job_id}.txt"
    val job_id into completed_jobs
    
    script:
    """
    # Simple CPU job
    echo "Running CPU job ${job_id}"
    
    # Do some simple CPU work
    for i in \$(seq 1 10); do
        echo "Processing iteration \$i" >> cpu_job_${job_id}.txt
        sleep \$[ ( \$RANDOM % 5 ) + 1 ]s  # Random sleep between 1-5 seconds
        
        # Some basic calculations
        bc <<< "scale=2000; a(1)*4" > /dev/null
    done
    
    # Write completion info
    echo "Job ${job_id} completed at \$(date)" >> cpu_job_${job_id}.txt
    echo "Hostname: \$(hostname)" >> cpu_job_${job_id}.txt
    echo "CPU details: \$(lscpu | grep 'Model name' || echo 'CPU info not available')" >> cpu_job_${job_id}.txt
    
    # Print completion message
    echo "Completed CPU job ${job_id}"
    """
}

// Process 2: Final report generation
process generateReport {
    tag "report"
    
    publishDir "${params.output_dir}", mode: 'copy', overwrite: true
    
    input:
    val all_jobs from completed_jobs.collect()
    
    output:
    file "stress_test_report.txt"
    
    script:
    """
    # Generate final report
    echo "=========================================" > stress_test_report.txt
    echo "SLURM CLUSTER STRESS TEST - FINAL REPORT" >> stress_test_report.txt
    echo "=========================================" >> stress_test_report.txt
    echo "Report generated at: \$(date)" >> stress_test_report.txt
    echo "" >> stress_test_report.txt
    
    echo "Test Parameters:" >> stress_test_report.txt
    echo "- Jobs submitted: ${params.job_count}" >> stress_test_report.txt
    echo "- Max CPUs: ${params.max_cpus}" >> stress_test_report.txt
    echo "- Max memory: ${params.max_memory}" >> stress_test_report.txt
    echo "" >> stress_test_report.txt
    
    echo "Jobs completed:" >> stress_test_report.txt
    echo "- CPU jobs: \$(ls -la ${params.output_dir}/cpu_jobs/cpu_job_*.txt | wc -l)" >> stress_test_report.txt
    echo "" >> stress_test_report.txt
    
    echo "Detailed job information:" >> stress_test_report.txt
    for job in ${params.output_dir}/cpu_jobs/cpu_job_*.txt; do
        echo "----------------------------------------" >> stress_test_report.txt
        echo "Job file: \$job" >> stress_test_report.txt
        tail -n 3 \$job >> stress_test_report.txt
        echo "" >> stress_test_report.txt
    done
    
    echo "Stress test completed successfully!" >> stress_test_report.txt
    """
}

// Final completion message
workflow.onComplete {
    log.info "========================================="
    log.info "Pipeline completed at: ${workflow.complete}"
    log.info "Execution status: ${workflow.success ? 'SUCCESS' : 'FAILED'}"
    log.info "Execution duration: ${workflow.duration}"
    log.info "Results available in: ${params.output_dir}"
    log.info "========================================="
}
