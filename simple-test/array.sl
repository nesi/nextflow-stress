#!/bin/bash -e

#SBATCH --time=5:00
#SBATCH --mem=500M
#SBATCH --cpus-per-task=1
#SBATCH --output=slog/%j.out

module purge

# Get the SLURM_ARRAY_TASK_ID
JOB_ID=$SLURM_ARRAY_TASK_ID

# Create output directory
mkdir -p results/direct_slurm

# Do some simple work
echo "Starting job $JOB_ID on $(hostname) at $(date)"
sleep $(( RANDOM % 10 + 5 ))  # Sleep 5-15 seconds
echo "Processing job $JOB_ID..."
for i in {1..10}; do
  echo "Iteration $i"
  # Some CPU work
  for j in {1..1000}; do
    echo "scale=1000; 4*a(1)" | bc -l > /dev/null
  done
done
echo "Job $JOB_ID completed on $(hostname) at $(date)" > results/direct_slurm/job_${JOB_ID}.txt
