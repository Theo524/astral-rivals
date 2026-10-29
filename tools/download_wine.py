#!/usr/bin/env python3
"""Fetch/extract Debian Wine locally for optional Windows-build smoke tests.

No system install, package scripts or SDK license acceptance. Run only on the
Debian 13 build host; HTTPS index and package SHA256 checks protect transfers.
"""
import argparse
import hashlib
import lzma
from pathlib import Path
import re
import shutil
import subprocess
import urllib.request

BASE = "https://deb.debian.org/debian/"

def records(text):
    result = {}
    for block in text.split("\n\n"):
        record = {}
        last = None
        for line in block.splitlines():
            if line.startswith(" ") and last:
                record[last] += " " + line.strip()
            elif ": " in line:
                last, value = line.split(": ", 1)
                record[last] = value
        if "Package" in record:
            result[record["Package"]] = record
    return result

def download(url, path):
    with urllib.request.urlopen(url, timeout=120) as response, path.open("wb") as out:
        while True:
            data = response.read(1024 * 1024)
            if not data:
                break
            out.write(data)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--destination", type=Path, default=Path("/workspace/toolchains/wine"))
    args = parser.parse_args()
    root = args.destination
    cache = root / "cache"
    cache.mkdir(parents=True, exist_ok=True)
    index = cache / "Packages.xz"
    if not index.exists():
        print("Downloading Debian13 package index", flush=True)
        download(BASE + "dists/trixie/main/binary-amd64/Packages.xz", index)
    packages = records(lzma.open(index, "rt").read())
    installed = set(subprocess.check_output(["dpkg-query", "-W", "-f=${Package}\\t${db:Status-Status}\\n"], text=True).splitlines())
    installed = {line.split("\t")[0] for line in installed if line.endswith("\tinstalled")}
    queue = ["wine64", "libwine"]
    wanted = set()
    while queue:
        name = queue.pop()
        if name in wanted:
            continue
        record = packages.get(name)
        if not record:
            raise SystemExit("Missing dependency from Debian13 index: " + name)
        wanted.add(name)
        for dependency in (record.get("Depends", "") + "," + record.get("Pre-Depends", "")).split(","):
            alternatives = [re.split(r"[ (:]", item.strip())[0] for item in dependency.split("|") if item.strip()]
            if not alternatives or any(item in installed or item in wanted for item in alternatives):
                continue
            available = next((item for item in alternatives if item in packages), None)
            if available:
                queue.append(available)
            else:
                raise SystemExit("Unavailable dependency: " + dependency)
    print("Local Wine packages: " + ", ".join(sorted(wanted)), flush=True)
    for name in sorted(wanted):
        record = packages[name]
        target = cache / Path(record["Filename"]).name
        expected = record["SHA256"]
        if not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest() != expected:
            print("Downloading " + name + " (" + record["Size"] + " bytes)", flush=True)
            download(BASE + record["Filename"], target)
        if hashlib.sha256(target.read_bytes()).hexdigest() != expected:
            raise SystemExit("SHA256 mismatch: " + str(target))
        subprocess.run(["dpkg-deb", "-x", str(target), str(root)], check=True)
    # Debian's dispatcher hardcodes /usr/lib/wine, which is inappropriate for
    # a local, uninstalled extraction. Keep dispatch relative to this tree.
    dispatcher = root / "usr/lib/wine/wineserver"
    dispatcher.write_text('#!/bin/sh\nexec "$(dirname -- "$0")/wineserver64" -p0 "$@"\n')
    dispatcher.chmod(0o755)
    # Debian compiles server relocation from /usr/lib/wine to the equivalent
    # /usr/share/wine/wine/nls; its system installation uses a fallback path.
    # Supply that relative layout locally, without writing /usr/share.
    data_alias = root / "usr/share/wine/wine"
    if not data_alias.exists():
        data_alias.symlink_to(".", target_is_directory=True)
    # Debian resolves this MinGW dependency through system DLL search paths.
    # A local Wine extraction needs it beside the other x64 built-in PE DLLs.
    shutil.copy2(root / "usr/x86_64-w64-mingw32/lib/zlib1.dll",
                 root / "usr/lib/x86_64-linux-gnu/wine/x86_64-windows/zlib1.dll")
    print("Wine extracted locally: " + str(root), flush=True)

if __name__ == "__main__":
    main()
