#!/bin/bash
# Launcher script for Slurm Cluster Stress Test Pipeline

# Set defaults
PROFILE="full"
RESUME=false
SAMPLES=100
SHORT=50
MEDIUM=30
LONG=20
FAILURE_RATE=0.05
OUTPUT_DIR="results"
MEM_TEST=true
CPU_TEST=true
IO_TEST=true
MAX_CPUS=16
MAX_MEM="32 GB"

# Function to display usage
usage() {
    echo "Slurm Cluster Stress Test Pipeline Launcher"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -p, --profile PROFILE     Run with specific profile (full, test, memtest, cputest, iotest)"
    echo "  -r, --resume              Resume previous run"
    echo "  -s, --samples N           Number of samples to process (default: 100)"
    echo "  --short N                 Number of short jobs (default: 50)"
    echo "  --medium N                Number of medium jobs (default: 30)"
    echo "  --long N                  Number of long jobs (default: 20)"
    echo "  -f, --failure RATE        Failure rate (0.0-1.0, default: 0.05)"
    echo "  -o, --output DIR          Output directory (default: results)"
    echo "  --no-mem                  Disable memory-intensive tests"
    echo "  --no-cpu                  Disable CPU-intensive tests"
    echo "  --no-io                   Disable I/O-intensive tests"
    echo "  --max-cpus N              Maximum CPUs per task (default: 16)"
    echo "  --max-memory MEM          Maximum memory per task (default: 32 GB)"
    echo "  -h, --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --profile test         Run a quick test with few jobs"
    echo "  $0 --samples 200 --long 50 Run with 200 samples and 50 long jobs"
    echo "  $0 --no-mem --no-io       Run only CPU-intensive tests"
    echo ""
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -p|--profile)
            PROFILE="$2"
            shift
            shift
            ;;
        -r|--resume)
            RESUME=true
            shift
            ;;
        -s|--samples)
            SAMPLES="$2"
            shift
            shift
            ;;
        --short)
            SHORT="$2"
            shift
            shift
            ;;
        --medium)
            MEDIUM="$2"
            shift
            shift
            ;;
        --long)
            LONG="$2"
            shift
            shift
            ;;
        -f|--failure)
            FAILURE_RATE="$2"
            shift
            shift
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift
            shift
            ;;
        --no-mem)
            MEM_TEST=false
            shift
            ;;
        --no-cpu)
            CPU_TEST=false
            shift
            ;;
        --no-io)
            IO_TEST=false
            shift
            ;;
        --max-cpus)
            MAX_CPUS="$2"
            shift
            shift
            ;;
        --max-memory)
            MAX_MEM="$2"
            shift
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Prepare command
CMD="nextflow run main.nf -profile $PROFILE"

# Add resume if specified
if [ "$RESUME" = true ]; then
    CMD="$CMD -resume"
fi

# Add parameters
CMD="$CMD --num_samples $SAMPLES"
CMD="$CMD --short_jobs $SHORT"
CMD="$CMD --medium_jobs $MEDIUM"
CMD="$CMD --long_jobs $LONG"
CMD="$CMD --failure_rate $FAILURE_RATE"
CMD="$CMD --output_dir $OUTPUT_DIR"
CMD="$CMD --mem_intensive $MEM_TEST"
CMD="$CMD --cpu_intensive $CPU_TEST"
CMD="$CMD --io_intensive $IO_TEST"
CMD="$CMD --max_cpus $MAX_CPUS"
CMD="$CMD --max_memory '$MAX_MEM'"

# Check if Nextflow is installed
if ! command -v nextflow &> /dev/null; then
    echo "Nextflow is not installed. Please install it first."
    echo "You can download it using:"
    echo "  curl -s https://get.nextflow.io | bash"
    exit 1
fi

# Create directory structure
mkdir -p "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/reports"

# Print configuration
echo "=================================="
echo "SLURM CLUSTER STRESS TEST LAUNCHER"
echo "=================================="
echo "Profile: $PROFILE"
echo "Resume: $RESUME"
echo "Samples: $SAMPLES"
echo "Short jobs: $SHORT"
echo "Medium jobs: $MEDIUM"
echo "Long jobs: $LONG"
echo "Failure rate: $FAILURE_RATE"
echo "Output directory: $OUTPUT_DIR"
echo "Memory tests: $MEM_TEST"
echo "CPU tests: $CPU_TEST"
echo "I/O tests: $IO_TEST"
echo "Max CPUs: $MAX_CPUS"
echo "Max memory: $MAX_MEM"
echo ""
echo "Command: $CMD"
echo "=================================="

# Ask for confirmation
read -p "Do you want to proceed? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Run the pipeline
echo "Starting stress test pipeline..."
eval "$CMD"

# Check pipeline exit status
if [ $? -eq 0 ]; then
    echo "=================================="
    echo "Stress test pipeline completed successfully!"
    echo "Results available in: $OUTPUT_DIR"
    echo "Reports available in: $OUTPUT_DIR/reports"
    echo "=================================="
else
    echo "=================================="
    echo "Stress test pipeline failed!"
    echo "Check the logs for more information."
    echo "=================================="
    exit 1
fi
