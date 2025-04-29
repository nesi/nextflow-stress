#!/bin/bash

# Configuration variables - modify as needed
OUTPUT_DIR="/nesi/nobackup/nesi99999/Dinindu/output"
JOBS=1000
FILE_SIZE_MB=100
READ_ITERATIONS=20
WRITE_ITERATIONS=20
CHUNK_SIZE_KB=1024
PROFILE="standard"  # Options: standard, light, heavy, debug

# Set Nextflow environment variables for NeSI
export NXF_OPTS="-Xms500M -Xmx4G"
export NXF_TEMP="/nesi/nobackup/nesi99999/Dinindu/nextflow-tmp"
export NXF_WORK="/nesi/nobackup/nesi99999/Dinindu/output/nf-temp"

# Create output and temp directories if they don't exist
mkdir -p $OUTPUT_DIR
mkdir -p $NXF_TEMP
mkdir -p $NXF_WORK

# Print banner
echo "============================================="
echo "   WEKA FILESYSTEM I/O STRESS TEST LAUNCHER"
echo "============================================="
echo "Output directory: $OUTPUT_DIR"
echo "Number of jobs: $JOBS"
echo "File size (MB): $FILE_SIZE_MB"
echo "Profile: $PROFILE"
echo "Starting test at: $(date)"
echo "NeSI Project: nesi99999"
echo "============================================="

# Run the Nextflow pipeline
nextflow run main.nf \
    -profile $PROFILE \
    --output_dir $OUTPUT_DIR \
    --jobs $JOBS \
    --file_size_mb $FILE_SIZE_MB \
    --read_iterations $READ_ITERATIONS \
    --write_iterations $WRITE_ITERATIONS \
    --chunk_size_kb $CHUNK_SIZE_KB \
    -with-report \
    -with-timeline \
    -with-dag \
    -resume

exit_code=$?

echo "============================================="
echo "Test completed at: $(date)"
echo "Exit code: $exit_code"
echo "Report available at: weka_stress_report.html"
echo "Timeline available at: weka_stress_timeline.html"
echo "DAG available at: weka_stress_dag.html"
echo "============================================="

exit $exit_code
