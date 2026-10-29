#!/usr/bin/env python3
"""Inspect a produced APK's archive and native ELF layout without a device.

This checks packaging facts only. It does NOT prove Android device compatibility,
runtime stability, permissions behavior, performance or touchscreen behavior.
Use the real apksigner verifier separately to validate its signature.
"""
import argparse
from pathlib import Path
import struct
import zipfile


def binary_manifest(data):
    """Decode Android's actual binary XML string pool and start-tag attributes."""
    strings = []
    tags = []
    position = struct.unpack_from("<H", data, 2)[0]
    while position + 8 <= len(data):
        kind, header_size, chunk_size = struct.unpack_from("<HHI", data, position)
        if chunk_size < header_size or position + chunk_size > len(data):
            raise ValueError("Invalid binary AndroidManifest chunk")
        if kind == 0x0001:  # RES_STRING_POOL_TYPE
            count, _, flags, string_start, _ = struct.unpack_from("<IIIII", data, position + 8)
            offsets = struct.unpack_from("<" + "I" * count, data, position + header_size)
            def length8(at):
                first = data[at]
                return (((first & 0x7f) << 8) | data[at + 1], at + 2) if first & 0x80 else (first, at + 1)
            def length16(at):
                first = struct.unpack_from("<H", data, at)[0]
                return (((first & 0x7fff) << 16) | struct.unpack_from("<H", data, at + 2)[0], at + 4) if first & 0x8000 else (first, at + 2)
            for offset in offsets:
                start = position + string_start + offset
                if flags & 0x100:
                    _, start = length8(start)
                    size, start = length8(start)
                    strings.append(data[start:start + size].decode("utf-8"))
                else:
                    size, start = length16(start)
                    strings.append(data[start:start + size * 2].decode("utf-16-le"))
        elif kind == 0x0102:  # RES_XML_START_ELEMENT_TYPE
            _, name, attribute_start, attribute_size, count = struct.unpack_from("<IIHHH", data, position + 16)
            attributes = {}
            start = position + 16 + attribute_start
            for index in range(count):
                at = start + index * attribute_size
                _, attr_name, raw = struct.unpack_from("<III", data, at)
                _, _, value_type, value = struct.unpack_from("<HBBI", data, at + 12)
                if raw != 0xffffffff:
                    decoded = strings[raw]
                elif value_type == 0x03:
                    decoded = strings[value]
                elif value_type == 0x12:
                    decoded = bool(value)
                elif value_type in [0x10, 0x11]:
                    decoded = value
                else:
                    decoded = f"resource/type{value_type:#x}:{value:#x}"
                attributes[strings[attr_name]] = decoded
            tags.append((strings[name], attributes))
        position += chunk_size
    return tags


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("apk", type=Path)
    parser.add_argument("--require-16k", action="store_true")
    args = parser.parse_args()
    failures = []
    with args.apk.open("rb") as raw, zipfile.ZipFile(args.apk) as apk:
        invalid = apk.testzip()
        if invalid:
            raise SystemExit("APK ZIP CRC failure: " + invalid)
        files = apk.namelist()
        for required in ["AndroidManifest.xml", "classes.dex"]:
            if required not in files:
                failures.append("Missing " + required)
        tags = binary_manifest(apk.read("AndroidManifest.xml"))
        manifest = next((attributes for tag, attributes in tags if tag == "manifest"), {})
        sdk = next((attributes for tag, attributes in tags if tag == "uses-sdk"), {})
        application = next((attributes for tag, attributes in tags if tag == "application"), {})
        activities = [attributes for tag, attributes in tags if tag == "activity"]
        print("Manifest package=" + str(manifest.get("package")) + ", versionCode=" + str(manifest.get("versionCode")) + ", versionName=" + str(manifest.get("versionName")))
        print("Manifest minSdkVersion=" + str(sdk.get("minSdkVersion")) + ", targetSdkVersion=" + str(sdk.get("targetSdkVersion")))
        extracts = application.get("extractNativeLibs", True)
        if isinstance(extracts, str):
            extracts = extracts.lower() not in ["false", "0"]
        print("Manifest extractNativeLibs=" + str(extracts) + (" (Android default; attribute absent)" if "extractNativeLibs" not in application else ""))
        for activity in activities:
            print("Activity " + str(activity.get("name")) + ": screenOrientation=" + str(activity.get("screenOrientation")))
        if manifest.get("package") != "org.astralrivals.game":
            failures.append("Unexpected manifest package identity")
        natives = [entry for entry in apk.infolist() if entry.filename.startswith("lib/arm64-v8a/") and entry.filename.endswith(".so")]
        if not natives:
            failures.append("No actual arm64-v8a shared library")
        print(f"ZIP CRC passed: {len(files)} entries, {args.apk.stat().st_size:,} bytes")
        for native in natives:
            raw.seek(native.header_offset)
            header = raw.read(30)
            name_length, extra_length = struct.unpack_from("<HH", header, 26)
            data_offset = native.header_offset + 30 + name_length + extra_length
            stored = native.compress_type == zipfile.ZIP_STORED
            archive_aligned = data_offset % 16384 == 0
            if stored:
                print(f"{native.filename}: stored, data offset={data_offset}, 16KiB ZIP aligned={archive_aligned}")
            else:
                print(f"{native.filename}: compressed; ZIP page alignment not applicable; requires extraction")
                if not extracts:
                    failures.append("Compressed native library conflicts with extractNativeLibs=false: " + native.filename)
            if args.require_16k and stored and not archive_aligned:
                failures.append("Stored native library lacks 16KiB ZIP alignment: " + native.filename)
            data = apk.read(native)
            if data[:6] != b"\x7fELF\x02\x01":
                failures.append("Expected actual little-endian ELF64: " + native.filename)
                continue
            program_offset = struct.unpack_from("<Q", data, 32)[0]
            entry_size, count = struct.unpack_from("<HH", data, 54)
            alignments = []
            for index in range(count):
                record = struct.unpack_from("<IIQQQQQQ", data, program_offset + index * entry_size)
                if record[0] == 1:  # PT_LOAD
                    alignments.append(record[-1])
            print("  ELF PT_LOAD alignments: " + ", ".join(str(value) for value in alignments))
            if args.require_16k and any(value < 16384 for value in alignments):
                failures.append("ELF PT_LOAD requires further 16KiB review: " + native.filename)
        assets = [name for name in files if name.startswith("assets/")]
        print(f"Embedded game asset entries: {len(assets)}")
        if not assets:
            failures.append("No embedded game assets")
    if failures:
        raise SystemExit("APK PACKAGING CHECK FAILED: " + "; ".join(failures))
    print("APK packaging checks passed; actual device execution remains unverified.")


if __name__ == "__main__":
    main()
