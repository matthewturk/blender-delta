#!/bin/bash
# Submit delta.env's frame range as a Slurm array of CHUNK-frame tasks.
# Extra arguments go to sbatch, e.g. ./submit.sh --partition=gpuA100x4
set -euo pipefail
BUNDLE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$BUNDLE"
source delta.env
tasks=$(( (LAST - FIRST + CHUNK) / CHUNK ))
mkdir -p logs
sbatch --array=0-$((tasks - 1)) "$@" render.sbatch
