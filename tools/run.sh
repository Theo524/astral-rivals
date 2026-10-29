#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
runtime_dir="${TMPDIR:-/tmp}/astral-rivals-runtime"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$runtime_dir/data}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$runtime_dir/cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$runtime_dir/config}"
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"
engine="${GODOT_BIN:-godot}"
exec "$engine" --path "$project_dir" "$@"
