#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${1:-$project_dir/build/windows}"
mkdir -p "$output_dir"
output_dir="$(cd -- "$output_dir" && pwd)"
# Preserve the caller's Godot/XDG profile so templates installed through the
# editor remain visible. Restricted build agents can set XDG_DATA_HOME first.
engine="${GODOT_BIN:-godot}"
"$engine" --headless --path "$project_dir" --export-release "Windows PC" "$output_dir/AstralRivals.exe"
test -s "$output_dir/AstralRivals.exe"
printf 'Windows build: %s\n' "$output_dir/AstralRivals.exe"
