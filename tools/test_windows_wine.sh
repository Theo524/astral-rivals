#!/usr/bin/env bash
set -euo pipefail
wine_root="${ASTRAL_WINE_ROOT:-/workspace/toolchains/wine}"
wine_binary="$wine_root/usr/lib/wine/wine64"
if [[ ! -x "$wine_binary" ]]; then
  printf 'Local Wine is not installed; run tools/download_wine.py first.\n' >&2
  exit 1
fi
export WINEPREFIX="${WINEPREFIX:-/workspace/toolchains/wine-prefix}"
mkdir -p "$WINEPREFIX/drive_c/windows/system32"
# MinGW's zlib is a native PE dependency of Debian Wine user32, rather than a
# Wine builtin. It must be on the Windows DLL search path during bootstrap.
if [[ -f "$wine_root/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/zlib1.dll" ]]; then
  cp "$wine_root/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/zlib1.dll" "$WINEPREFIX/drive_c/windows/system32/zlib1.dll"
fi
export WINEARCH=win64
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$wine_root/runtime/cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$wine_root/runtime/config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$wine_root/runtime/data}"
mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
# Wine adds the architecture suffix itself. Passing an already suffixed path
# makes its built-in PE DLL lookup miss kernel32 and other runtime modules.
export WINEDLLPATH="$wine_root/usr/lib/x86_64-linux-gnu/wine"
export LD_LIBRARY_PATH="$wine_root/usr/lib/x86_64-linux-gnu:$wine_root/usr/lib/x86_64-linux-gnu/wine/x86_64-unix:${LD_LIBRARY_PATH:-}"
export WINESERVER="$wine_root/usr/lib/wine/wineserver"
export WINELOADER="$wine_binary"
export WINEDATADIR="$wine_root/usr/share/wine"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=;winegstreamer=;winemenubuilder.exe=d}"
game_exe="${1:-/workspace/releases/windows/AstralRivals.exe}"
shift || true
exec "$wine_binary" "$game_exe" "$@"
