#!/usr/bin/env python3
"""Extract selected matching Godot templates without downloading a 1.2 GB ZIP.

Uses ordinary HTTPS proxy settings and verifies server HTTP Range responses.
No credentials are read, printed, or embedded. Only selected ZIP members are
extracted to Godot's versioned export-template directory.
"""
from __future__ import annotations

import argparse
import io
import os
from pathlib import Path
import shutil
import time
import urllib.request
import zipfile


class RemoteZip(io.RawIOBase):
    def __init__(self, url: str, chunk_size: int = 8 * 1024 * 1024):
        self._url = url
        self._position = 0
        self._chunk_size = chunk_size
        self._cache_start = 0
        self._cache = b""
        self.bytes_downloaded = 0
        request = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "AstralRivals-build/0.2"})
        with urllib.request.urlopen(request, timeout=45) as response:
            self._size = int(response.headers["Content-Length"])
            self._url = response.geturl()

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self._position

    def seek(self, offset, whence=io.SEEK_SET):
        if whence == io.SEEK_CUR:
            offset += self._position
        elif whence == io.SEEK_END:
            offset += self._size
        if offset < 0:
            raise ValueError("Negative seek")
        self._position = offset
        return offset

    def read(self, size=-1):
        if size < 0:
            size = self._size - self._position
        if size == 0 or self._position >= self._size:
            return b""
        size = min(size, self._size - self._position)
        start = self._position
        cache_end = self._cache_start + len(self._cache)
        if not (self._cache_start <= start and start + size <= cache_end):
            # ZIP metadata lives near EOF. Avoid fetching a whole block for it.
            near_end = start > self._size - 2 * 1024 * 1024
            fetch_size = size if near_end else max(size, self._chunk_size)
            stop = min(start + fetch_size, self._size) - 1
            headers = {"Range": f"bytes={start}-{stop}", "User-Agent": "AstralRivals-build/0.2"}
            last_error = None
            for attempt in range(4):
                try:
                    request = urllib.request.Request(self._url, headers=headers)
                    with urllib.request.urlopen(request, timeout=90) as response:
                        expected = f"bytes {start}-{stop}/{self._size}"
                        if response.status != 206 or response.headers.get("Content-Range") != expected:
                            raise RuntimeError("Server did not honor exact HTTP Range; refusing a full archive download")
                        data = response.read()
                    if len(data) != stop - start + 1:
                        raise IOError("Incomplete HTTP Range response")
                    self._cache_start = start
                    self._cache = data
                    self.bytes_downloaded += len(data)
                    break
                except Exception as error:
                    last_error = error
                    if attempt == 3:
                        raise
                    time.sleep(1 + attempt)
            if last_error is not None and not self._cache:
                raise last_error
        relative = start - self._cache_start
        data = self._cache[relative:relative + size]
        self._position += len(data)
        return data


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", default="4.6.3")
    parser.add_argument("--data-dir", type=Path, default=Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")))
    parser.add_argument("--windows", action="store_true")
    parser.add_argument("--android", action="store_true")
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    version = args.version
    url = f"https://github.com/godotengine/godot/releases/download/{version}-stable/Godot_v{version}-stable_export_templates.tpz"
    destination = args.data_dir / "godot/export_templates" / f"{version}.stable"
    destination.mkdir(parents=True, exist_ok=True)
    desired = {"version.txt"}
    if args.windows:
        desired.update({"windows_debug_x86_64.exe", "windows_release_x86_64.exe"})
    if args.android:
        desired.update({"android_debug.apk", "android_release.apk"})
    if not (args.windows or args.android or args.list):
        parser.error("Choose --windows, --android, or --list")
    remote = RemoteZip(url)
    print(f"Matching export archive: {remote._size:,} bytes; extracting selected members only.", flush=True)
    with zipfile.ZipFile(remote) as archive:
        if args.list:
            for member in archive.infolist():
                print(f"{member.filename}: {member.file_size:,} bytes ({member.compress_size:,} compressed)")
        for member in archive.infolist():
            name = Path(member.filename).name
            if name not in desired:
                continue
            target = destination / name
            if target.is_file() and target.stat().st_size == member.file_size:
                print(f"Already installed: {name}", flush=True)
                desired.remove(name)
                continue
            print(f"Extracting {name} ({member.file_size:,} bytes)", flush=True)
            temporary = target.with_name(target.name + ".part")
            with archive.open(member) as incoming, temporary.open("wb") as output:
                shutil.copyfileobj(incoming, output, length=1024 * 1024)
            temporary.replace(target)
            desired.remove(name)
    if desired:
        raise SystemExit("Missing requested members: " + ", ".join(sorted(desired)))
    print(f"Installed to {destination}; downloaded {remote.bytes_downloaded:,} compressed bytes.", flush=True)


if __name__ == "__main__":
    main()
