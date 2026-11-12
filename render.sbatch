#!/bin/bash
# One task of the frame-range array; submit with submit.sh, which sets --array.
#SBATCH --job-name=yt-volumes
#SBATCH --account=bcdj-delta-gpu
#SBATCH --partition=gpuA40x4
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --gpus-per-node=1
#SBATCH --mem=64g
#SBATCH --time=02:00:00
#SBATCH --output=logs/%x-%A_%a.out
set -euo pipefail
# Slurm runs a copy of this script, so find the bundle from the submit directory
BUNDLE=$SLURM_SUBMIT_DIR
source "$BUNDLE/delta.env"
start=$((FIRST + SLURM_ARRAY_TASK_ID * CHUNK))
end=$((start + CHUNK - 1))
if [ "$end" -gt "$LAST" ]; then end=$LAST; fi
echo "task $SLURM_ARRAY_TASK_ID: frames $start-$end on $(hostname)"
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
exec "$BUNDLE/render_frames.sh" "$start" "$end"
