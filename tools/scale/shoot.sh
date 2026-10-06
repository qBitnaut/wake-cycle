#!/usr/bin/env bash
# Scale study: render one variant at one window size.  shoot.sh <A|B|C|D> <W>x<H> <out_prefix> [still|strip]
set -euo pipefail
cd "$(dirname "$0")/../.."
v=$1; size=$2; out=$3; mode=${4:-still}
fps=30; [ "$mode" = strip ] && fps=60
timeout 240 xvfb-run -a -s "-screen 0 ${size}x24" godot --path . --rendering-driver opengl3 \
  --fixed-fps $fps --resolution "$size" --position 0,0 \
  --script res://tools/scale/mock.gd -- --skip-intro "$v" "$out" "$mode" 2>&1 | grep -E "SHOT|ERROR|SCRIPT" || true
