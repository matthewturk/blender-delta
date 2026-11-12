#!/bin/bash
# Pack a render_volume config, its .blend and the yt-volumes add-on into a uv
# project that renders on an HPC cluster with the pip `bpy`.
#
#   ADDON=CHECKOUT YT_IDV=SOURCE ./make_bundle.sh CONFIG.toml [OUT_DIR]
#
# ADDON is a yt-volumes (blender-yt-volumes) checkout; its working tree is
# packed as is.
# YT_IDV is a requirement, e.g. "yt_idv>=0.6.2" or
# "yt_idv @ git+https://github.com/OWNER/yt_idv@BRANCH", or a local yt_idv
# git checkout, whose HEAD is packed as an sdist. yt and the rest come from
# PyPI, pinned in the bundle's uv.lock. The dataset isn't packed: copy it
# separately and set DATA in the bundle's delta.env.
set -euo pipefail

if [ $# -lt 1 ] || [ -z "${YT_IDV:-}" ] || [ -z "${ADDON:-}" ]; then
    sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
fi
config=$(realpath "$1")
out=$(realpath -m "${2:-delta_bundle}")
here=$(cd "$(dirname "$0")" && pwd)
repo=$(realpath "$ADDON")
[ -d "$repo/src/yt_volumes" ] || { echo "make_bundle: $repo is not a yt-volumes checkout" >&2; exit 1; }

# the .blend the config names, and which data key holds the dataset path
read -r blend data_key < <(python3 - "$config" <<'PY'
import os, sys, tomllib
path = sys.argv[1]
config = tomllib.load(open(path, "rb"))
blend = config.get("blender", {}).get("file")
if not blend:
    sys.exit("make_bundle: the config has no blender.file")
data = config.get("data", {})
keys = [k for k in ("scene", "path") if data.get(k)]
if len(keys) != 1:
    sys.exit("make_bundle: the config needs exactly one of data.scene or data.path")
print(os.path.normpath(os.path.join(os.path.dirname(path), os.path.expanduser(blend))), "data." + keys[0])
PY
)
[ -f "$blend" ] || { echo "make_bundle: $blend does not exist" >&2; exit 1; }

rm -rf "$out"
mkdir -p "$out/scene" "$out/cycles-yt/src" "$out/cycles-yt/extensions"
cp "$config" "$out/scene/render.toml"
cp "$blend" "$out/scene/"
skip=(--exclude=__pycache__ --exclude='*.pyc')
rsync -a "${skip[@]}" "$repo/src/yt_volumes" "$out/cycles-yt/src/"
rsync -a "${skip[@]}" "$repo/extensions/deep_zoom" "$out/cycles-yt/extensions/"
cp "$repo/LICENSE" "$out/cycles-yt/"

sources=""
if [ -d "$YT_IDV" ]; then
    checkout=$(realpath "$YT_IDV")
    if ! git -C "$checkout" diff --quiet HEAD; then
        echo "make_bundle: warning: $checkout has uncommitted changes; only HEAD is packed" >&2
    fi
    tree=$(mktemp -d)
    trap 'rm -rf "$tree"' EXIT
    git -C "$checkout" archive --format=tar HEAD | tar -x -C "$tree"
    mkdir -p "$out/vendor"
    uv build --quiet --sdist --out-dir "$out/vendor" "$tree"
    sdist=$(cd "$out/vendor" && ls yt_idv-*.tar.gz)
    requirement="yt_idv"
    sources=$'\n[tool.uv.sources]\nyt_idv = { path = "vendor/'"$sdist"$'" }\n'
    yt_idv_note="yt_idv $(git -C "$checkout" rev-parse --short HEAD) ($(git -C "$checkout" branch --show-current)) from $checkout, as vendor/$sdist"
else
    requirement=$YT_IDV
    yt_idv_note="yt_idv: $YT_IDV"
fi

cat > "$out/pyproject.toml" <<TOML
[project]
name = "yt-volumes-render"
version = "0"
requires-python = "==3.13.*"  # bpy 5.2 wheels are built for CPython 3.13
dependencies = [
    "bpy==5.2.0",
    "yt",
    "h5py",
    "pooch",
    "$requirement",
]

[tool.uv]
package = false
environments = ["sys_platform == 'linux' and platform_machine == 'x86_64'"]
$sources
TOML
(cd "$out" && uv lock --quiet)

for f in README.md setup_env.sh render_frames.sh render.sbatch submit.sh; do
    cp "$here/$f" "$out/"
done
sed -e "s|^BLEND=.*|BLEND=\"$(basename "$blend")\"|" -e "s|^DATA_KEY=.*|DATA_KEY=\"$data_key\"|" \
    "$here/delta.env.example" > "$out/delta.env"
{
    echo "blender-delta $(git -C "$here" rev-parse --short HEAD 2>/dev/null || echo unknown)$(git -C "$here" diff --quiet HEAD 2>/dev/null || echo ' + uncommitted changes')"
    echo "yt-volumes $(git -C "$repo" rev-parse --short HEAD) ($(git -C "$repo" branch --show-current)) from $repo$(git -C "$repo" diff --quiet HEAD || echo ' + uncommitted changes')"
    echo "$yt_idv_note"
    echo "config $config"
    echo "built $(date -Iseconds)"
} > "$out/MANIFEST.txt"

tar -czf "$out.tar.gz" -C "$(dirname "$out")" "$(basename "$out")"
echo "wrote $out.tar.gz ($(du -h "$out.tar.gz" | cut -f1)); dataset ($data_key) not included"
