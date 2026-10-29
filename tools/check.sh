#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_runtime="$(mktemp -d "${TMPDIR:-/tmp}/astral-rivals-check.XXXXXX")"
trap 'rm -rf -- "$test_runtime"' EXIT
export XDG_DATA_HOME="$test_runtime/data"
export XDG_CONFIG_HOME="$test_runtime/config"
export XDG_CACHE_HOME="$test_runtime/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"
engine="${GODOT_BIN:-godot}"
for suite in combat energy ui game animation; do
  log_path="$test_runtime/$suite.log"
  if ! "$engine" --headless --path "$project_dir" --fixed-fps 60 --script "res://tests/${suite}_tests.gd" >"$log_path" 2>&1; then
    cat "$log_path"
    exit 1
  fi
  if rg -n '^SCRIPT ERROR:|^ERROR:|^FAIL:|Leaked instance|ObjectDB instances leaked' "$log_path"; then
    cat "$log_path"
    exit 1
  fi
  rg -i 'tests:|passed|checks' "$log_path" | tail -3
done
printf 'All Godot regression suites passed.\n'
