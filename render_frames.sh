#!/bin/bash
# Render frames START-END of the bundle's scene, as configured in delta.env.
#   ./render_frames.sh START END
set -euo pipefail
BUNDLE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$BUNDLE/delta.env"
start=$1
end=$2

mkdir -p "$OUT/logs"
# a private work_dir: render sessions sweep leftover frame directories in theirs
work=$(mktemp -d "${TMPDIR:-/tmp}/yt_volumes.XXXXXX")
nvidia-smi --query-gpu=timestamp,memory.used,utilization.gpu --format=csv,noheader -l 5 \
    > "$OUT/logs/gpu_$start-$end.csv" 2>/dev/null &
monitor=$!
trap 'kill $monitor 2>/dev/null; rm -rf "$work"' EXIT

# yt_idv's EGL context needs this before anything imports PyOpenGL
export PYOPENGL_PLATFORM=egl
export PYTHONPATH="$BUNDLE/cycles-yt/src"
"$BUNDLE/.venv/bin/python" -m yt_volumes.render_volume "$BUNDLE/scene/render.toml" \
    --frames "$start-$end" \
    --set "blender.file=$BUNDLE/scene/$BLEND" \
    --set "blender.extensions=[\"$BUNDLE/cycles-yt/extensions/deep_zoom\"]" \
    --set "$DATA_KEY=$DATA" \
    --set "blender.output=$OUT/frame_" \
    --set "blender.work_dir=$work" \
    --report "$OUT/logs/report_$start-$end.json"
