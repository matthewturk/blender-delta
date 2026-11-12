# Rendering on Delta (or another Slurm cluster) with the pip `bpy`

These scripts pack a `render_volume` config, its `.blend` and the
[yt-volumes](https://github.com/matthewturk/blender-yt-volumes) Blender add-on
into a small uv project, build its environment on the cluster from the bundled
`uv.lock`, and render the frame range as a Slurm job array. No Blender install
is needed: the pip `bpy` 5.2 renders Cycles headless, and yt_idv draws through EGL.

## 1. Pack the bundle (here)

```
ADDON=~/yt/cycles-yt YT_IDV=~/dxl/yt_idv-raytable ./make_bundle.sh my_render.toml /data/delta_bundle
```

- The config is a normal `render_volume` TOML (see the add-on's
  `examples/render_volume.toml`, and `examples/` here).
  Its paths are overridden on the cluster, so it can keep local ones.
- `ADDON` is a yt-volumes checkout. Its working tree is packed as is,
  uncommitted changes included, so check out the branch you want first.
- `YT_IDV` is a local yt_idv git checkout, whose HEAD is packed as an sdist in
  `vendor/`, or a requirement such as `"yt_idv>=0.6.2"` or
  `"yt_idv @ git+https://github.com/OWNER/yt_idv@BRANCH"`. yt and everything
  else come from PyPI, pinned in `uv.lock`.
- `MANIFEST.txt` in the bundle records what went in.

## 2. Copy the bundle and the dataset

```
scp /data/delta_bundle.tar.gz login.delta.ncsa.illinois.edu:/work/hdd/bcdj/$USER/
scp dataset.zip login.delta.ncsa.illinois.edu:/work/hdd/bcdj/$USER/
```

Globus is faster for large datasets. Home works too, but has a smaller quota.

## 3. Build the environment (on a login node, once)

```
tar -xzf delta_bundle.tar.gz && cd delta_bundle
$EDITOR delta.env      # DATA, OUT, and the frame range
./setup_env.sh         # uv sync --frozen into .venv, then a quick import check
```

A vendored yt_idv sdist compiles two small Cython modules; if that can't find a
compiler, `module load gcc` and rerun.

## 4. Test a few frames on an interactive GPU node

```
srun --account=bcdj-delta-gpu --partition=gpuA40x4-interactive --gpus-per-node=1 \
     --cpus-per-task=16 --mem=64g --time=00:30:00 --pty bash
./render_frames.sh 1000 1002
```

Frame 1 of each run pays the dataset load. Check that `nvidia-smi` shows the
render on one GPU, and look at a frame before submitting the full range.

## 5. Submit

```
./submit.sh                      # an array of CHUNK-frame tasks over FIRST-LAST
./submit.sh --partition=gpuA100x4  # extra arguments go to sbatch
```

Each task loads the dataset once, then renders its chunk. Slurm logs go to
`logs/`, and each task writes a GPU memory trace and a JSON report to
`$OUT/logs/`. A failed chunk can be rerun by hand with `render_frames.sh`.

The A40 partitions are the better fit for Cycles: they have RT cores, which
OptiX uses. The A100s have none.

## Stereo

`blender.stereo` in the config (it needs a yt-volumes whose `render_volume`
has the key) picks the stereo layout: `"TOPBOTTOM"` (left eye
on top, what 360 video players expect), `"SIDEBYSIDE"`, `"INDIVIDUAL"` (a file
per eye) or `"OFF"`. Unset, the `.blend`'s own output settings apply.

To make a headset video from top-bottom 360 frames:

```
ffmpeg -framerate 24 -start_number 1 -i frame_%04d.png -c:v libx265 -crf 18 \
       -pix_fmt yuv420p -tag:v hvc1 name_360_TB.mp4
```
