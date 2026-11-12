#!/bin/bash
# Build the bundle's environment from its uv.lock (into .venv). Run once, from a login node.
set -euo pipefail
BUNDLE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
unset PYTHONPATH

if ! command -v uv >/dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi
uv sync --frozen --project "$BUNDLE"

PYOPENGL_PLATFORM=egl PYTHONPATH="$BUNDLE/cycles-yt/src" "$BUNDLE/.venv/bin/python" - <<'PY'
import bpy, yt, yt_idv
from yt_idv.cameras.base_camera import BaseCamera
assert "ray_table" in BaseCamera.projection_type.values, "this yt_idv has no ray_table projection"
import yt_volumes.render_volume
print(f"ok: bpy {bpy.app.version_string}, yt {yt.__version__}, yt_idv {yt_idv.__version__}")
PY
