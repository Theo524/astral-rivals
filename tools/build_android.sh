#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${1:-$project_dir/build/android}"
mkdir -p "$output_dir"
output_dir="$(cd -- "$output_dir" && pwd)"
# A debug export uses the locally configured debug keystore. Release keystores
# and passwords belong in Godot's local editor/export credentials, not source.
engine="${GODOT_BIN:-godot}"
"$engine" --headless --path "$project_dir" --export-debug Android "$output_dir/AstralRivals.apk"
test -s "$output_dir/AstralRivals.apk"
printf 'Android debug APK: %s\n' "$output_dir/AstralRivals.apk"
