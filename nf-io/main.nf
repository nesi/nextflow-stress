#!/usr/bin/env nextflow

// Define parameters with defaults
params.output_dir = "/nesi/nobackup/nesi99999/Dinindu/output"
params.jobs = 1000
params.file_size_mb = 100
params.read_iterations = 20
params.write_iterations = 20
params.chunk_size_kb = 1024

// Print pipeline info
log.info """
         WEKA FILESYSTEM I/O STRESS TEST
         ===============================
         Output directory: ${params.output_dir}
         Number of jobs: ${params.jobs}
         File size (MB): ${params.file_size_mb}
         Read iterations: ${params.read_iterations}
         Write iterations: ${params.write_iterations}
         Chunk size (KB): ${params.chunk_size_kb}
         """

// Create a channel with job IDs
jobIDs = Channel.from(1..params.jobs)

// Process for creating write-intensive workload
process writeStressTest {
    tag "write_job_${job_id}"
    
    // Slurm executor config - NeSI specific
    executor 'slurm'
    clusterOptions '--account=nesi99999 --partition=genoa2 --time=01:00:00'
    cpus 1
    memory '2 GB'
    
    // Error strategy to handle failures
    errorStrategy 'retry'
    maxRetries 3
    
    input:
    val job_id from jobIDs
    
    output:
    tuple val(job_id), path("test_file_${job_id}*.dat") into writeOutputs
    
    script:
    """
    # Create a directory for this job
    mkdir -p ${params.output_dir}/job_${job_id}
    
    # Perform multiple write operations with progress feedback
    for ((i=1; i<=${params.write_iterations}; i++)); do
        echo "Write iteration \$i for job ${job_id}"
        
        # Generate a file with random data of specified size using dd with status=progress
        dd if=/dev/urandom of=${params.output_dir}/job_${job_id}/test_file_${job_id}_\${i}.dat bs=${params.chunk_size_kb}k count=${ params.file_size_mb * 1024 / params.chunk_size_kb } status=progress
        
        # Copy the file to work directory (for passing to next process)
        cp ${params.output_dir}/job_${job_id}/test_file_${job_id}_\${i}.dat test_file_${job_id}_\${i}.dat
        
        # Sync to ensure data is written to disk
        sync
        
        # Calculate and report write speed
        echo "File size: ${params.file_size_mb} MB"
        ls -lh ${params.output_dir}/job_${job_id}/test_file_${job_id}_\${i}.dat
    done
    """
}

// Process for creating read-intensive workload
process readStressTest {
    tag "read_job_${job_id}"
    
    // Slurm executor config - NeSI specific
    executor 'slurm'
    clusterOptions '--account=nesi99999 --partition=milan --time=01:00:00'
    cpus 1
    memory '2 GB'
    
    // Error strategy to handle failures
    errorStrategy 'retry'
    maxRetries 3
    
    input:
    tuple val(job_id), path(files) from writeOutputs
    
    output:
    val job_id into readOutputs
    
    script:
    """
    # Perform multiple read operations
    for file in ${files}; do
        for ((i=1; i<=${params.read_iterations}; i++)); do
            echo "Read iteration \$i for job ${job_id} on file \$file"
            
            # Read the file and calculate checksum to ensure it's actually being read
            md5sum \$file > checksum_\${file}_\${i}.md5
            
            # Read the file with dd to /dev/null with status reporting
            dd if=\$file of=/dev/null bs=${params.chunk_size_kb}k status=progress
            
            # Try to drop caches if possible (may not have sudo access on NeSI)
            # Instead flush filesystem caches
            sync
            
            # Sleep briefly to ensure any caching effects are minimized
            sleep 2
        done
    done
    
    # Report total read operations completed
    echo "Completed ${params.read_iterations} read operations for each of ${files.size()} files"
    """
}

// Process for cleanup operations
process cleanup {
    tag "cleanup_job_${job_id}"
    
    // Slurm executor config - NeSI specific
    executor 'slurm'
    clusterOptions '--account=nesi99999 --partition=milan --time=00:10:00'
    cpus 1
    
    input:
    val job_id from readOutputs
    
    script:
    """
    # Get stats on the files created
    echo "File stats for job ${job_id}:"
    du -sh ${params.output_dir}/job_${job_id} || echo "Directory may already be cleaned"
    
    # Optional: Remove the files created for this job
    # Uncomment if you want to clean up after the test
    # rm -rf ${params.output_dir}/job_${job_id}
    
    echo "Completed I/O stress test for job ${job_id}"
    date  # Record completion time
    """
}

workflow.onComplete {
    log.info "Pipeline completed at: $workflow.complete"
    log.info "Execution status: ${ workflow.success ? 'SUCCESS' : 'FAILED' }"
    log.info "Execution duration: $workflow.duration"
}
