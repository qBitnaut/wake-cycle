#!/bin/sh
# Export the Web preset. Usage: tools/export_web.sh <debug|release> <out_dir>
#   debug   for the web audits (tools/audit/web_*.mjs): the window.wake* hooks, the
#           window.__wake/__map/__goo state, the ?start= deep links and the test-room hotkeys
#           exist only in a debug export (they are gated on OS.is_debug_build()).
#   release for the itch.io build: none of those exist.
set -e
mode="$1"
out="$2"
case "$mode" in debug|release) ;; *) echo "usage: $0 <debug|release> <out_dir>" >&2; exit 2 ;; esac
[ -n "$out" ] || { echo "usage: $0 <debug|release> <out_dir>" >&2; exit 2; }
cd "$(dirname "$0")/.."
mkdir -p "$out"
godot --headless --path . "--export-$mode" "Web" "$(cd "$out" && pwd)/index.html"
