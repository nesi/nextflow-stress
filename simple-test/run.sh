#!/bin/bash
# Simple run script for Slurm stress test

# Default parameters
PROFILE="test"
JOB_COUNT=10
OUTPUT_DIR="results"
MAX_CPUS=4
MAX_MEMORY="4 GB"

# Parse command line options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -p|--profile)
            PROFILE="$2"
            shift
            shift
            ;;
        -j|--jobs)
            JOB_COUNT="$2"
            shift
            shift
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift
            shift
            ;;
        --cpus)
            MAX_CPUS="$2"
            shift
            shift
            ;;
        --memory)
            MAX_MEMORY="$2"
            shift
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  -p, --profile PROFILE  Run profile (test, medium, full)"
            echo "  -j, --jobs N           Number of jobs to run"
            echo "  -o, --output DIR       Output directory"
            echo "  --cpus N               Maximum CPUs per job"
            echo "  --memory MEM           Maximum memory per job"
            echo "  -h, --help             Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Create output directory
mkdir -p "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/reports"

# Print run configuration
echo "====================================="
echo "SIMPLE SLURM STRESS TEST"
echo "====================================="
echo "Profile: $PROFILE"
echo "Jobs: $JOB_COUNT"
echo "Output directory: $OUTPUT_DIR"
echo "Max CPUs per job: $MAX_CPUS"
echo "Max memory per job: $MAX_MEMORY"
echo "====================================="

# Build command
CMD="nextflow run main.nf -profile $PROFILE --job_count $JOB_COUNT --output_dir $OUTPUT_DIR --max_cpus $MAX_CPUS --max_memory '$MAX_MEMORY'"

# Confirm and run
read -p "Do you want to proceed? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo "Running stress test..."
eval "$CMD"

# Check exit status
if [ $? -eq 0 ]; then
    echo "====================================="
    echo "Stress test completed successfully!"
    echo "Results available in: $OUTPUT_DIR"
    echo "====================================="
else
    echo "====================================="
    echo "Stress test failed!"
    echo "Check logs for details."
    echo "====================================="
    exit 1
fi
