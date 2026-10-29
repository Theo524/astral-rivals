#!/usr/bin/env python3
"""Assemble real open-source Debian Android APK tools locally, without SDK terms.

This is only the non-Gradle APK patch/sign toolchain: no Google platform SDK,
Gradle build or fake executables. Debian package copyright notices are retained.
Run on Debian13. The build host's ordinary HTTPS proxy settings are preserved.
"""
import argparse
import hashlib
import lzma
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from download_wine import BASE, download, records


def executable_wrapper(path, command, library_path=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = ["#!/bin/sh", "set -eu"]
    if library_path:
        lines.append("export LD_LIBRARY_PATH=" + shlex.quote(library_path) + '${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}')
    lines.append("exec " + " ".join(shlex.quote(str(item)) for item in command) + ' "$@"')
    path.write_text("\n".join(lines) + "\n")
    path.chmod(0o755)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--destination", type=Path, default=Path("/workspace/toolchains/android-tools"))
    parser.add_argument("--index", type=Path, default=Path("/workspace/toolchains/wine/cache/Packages.xz"))
    args = parser.parse_args()
    root = args.destination.resolve()
    cache = root / "cache"
    cache.mkdir(parents=True, exist_ok=True)
    index = args.index
    if not index.exists():
        index = cache / "Packages.xz"
        if not index.exists():
            download(BASE + "dists/trixie/main/binary-amd64/Packages.xz", index)
    packages = records(lzma.open(index, "rt").read())
    installed_lines = subprocess.check_output(["dpkg-query", "-W", "-f=${Package}\t${db:Status-Status}\n"], text=True).splitlines()
    installed = {line.split("\t")[0] for line in installed_lines if line.endswith("\tinstalled")}
    # Both JDK/JRE are explicit to keep Java's tools and runtime at one version.
    queue = ["adb", "apksigner", "zipalign", "openjdk-21-jdk-headless", "openjdk-21-jre-headless"]
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
            # This virtual runtime is supplied by our explicitly downloaded JRE.
            if any(item.startswith("java") and item.endswith("runtime") for item in alternatives):
                continue
            available = next((item for item in alternatives if item in packages), None)
            if available:
                queue.append(available)
            else:
                raise SystemExit("Unavailable dependency: " + dependency)
    print("Local Android/JDK packages: " + ", ".join(sorted(wanted)), flush=True)
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
    sdk = root / "sdk"
    # Debian's native adb/zipalign need relocated Android shared libraries.
    library_path = ":".join(str(p) for p in [root / "usr/lib/x86_64-linux-gnu/android", root / "usr/lib/x86_64-linux-gnu", root / "usr/lib/7zip"])
    def actual_tool(name):
        choices = [root / "usr/lib/android-sdk/platform-tools" / name,
                   root / "usr/lib/android-sdk/build-tools/debian" / name,
                   root / "usr/bin" / name]
        for candidate in choices:
            if candidate.exists() and not candidate.is_symlink():
                return candidate
        matches = [p for p in root.rglob(name) if p.is_file() and not p.is_symlink() and p.parent != sdk]
        if not matches:
            raise SystemExit("Extracted package did not provide " + name)
        return matches[0]
    executable_wrapper(sdk / "platform-tools/adb", [actual_tool("adb")], library_path)
    build_tools = sdk / "build-tools/35.0.2"
    executable_wrapper(build_tools / "zipalign", [actual_tool("zipalign")], library_path)
    jars = [p for p in (root / "usr/share/java").glob("apksigner*.jar") if not p.is_symlink()]
    if not jars:
        raise SystemExit("No actual apksigner jar found in extracted packages")
    java_home = root / "usr/lib/jvm/java-21-openjdk-amd64"
    # Debian normally links JDK configuration into /etc. Copy those actual
    # extracted configuration files locally so no root-system install is needed.
    local_conf = root / "etc/java-21-openjdk"
    conf_link = java_home / "conf"
    if conf_link.is_symlink():
        conf_link.unlink()
        shutil.copytree(local_conf, conf_link, symlinks=False)
    executable_wrapper(build_tools / "apksigner", [java_home / "bin/java", "-jar", jars[0]], library_path)
    (sdk / "platform-tools/source.properties").write_text("Pkg.Desc=Android SDK Platform-Tools (Debian open-source tools)\nPkg.Revision=34.0.5\n")
    (build_tools / "source.properties").write_text("Pkg.Desc=Android APK signing/alignment tools (Debian)\nPkg.Revision=35.0.2\n")
    for name, command in [("adb", [sdk / "platform-tools/adb", "version"]),
                          ("zipalign", [build_tools / "zipalign", "-h"]),
                          ("apksigner", [build_tools / "apksigner", "version"]),
                          ("java", [java_home / "bin/java", "-version"]),
                          ("jarsigner", [java_home / "bin/jarsigner", "-help"])]:
        result = subprocess.run([str(x) for x in command], capture_output=True, text=True)
        print(f"{name} exit{result.returncode}: " + (result.stdout + result.stderr).splitlines()[0], flush=True)
        if name == "zipalign" and (result.returncode not in [0, 1, 2] or "alignment" not in (result.stdout + result.stderr).lower()):
            raise SystemExit("zipalign tool could not print its actual usage; check shared libraries")
        if name != "zipalign" and result.returncode != 0:
            raise SystemExit(name + " tool verification failed")
    print("ANDROID_SDK_PATH=" + str(sdk), flush=True)
    print("JAVA_SDK_PATH=" + str(java_home), flush=True)
    print("No Google SDK license was accepted; only real Debian-distributed tools were extracted.", flush=True)


if __name__ == "__main__":
    main()
