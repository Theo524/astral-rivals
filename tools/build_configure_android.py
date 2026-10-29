#!/usr/bin/env python3
"""Configure a LOCAL debug APK export profile; never a release signing identity."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--toolchain", type=Path, default=Path("/workspace/toolchains/android-tools"))
    parser.add_argument("--config-dir", type=Path, default=Path(os.environ.get("XDG_CONFIG_HOME", "/workspace/toolchains/godot-config")))
    args = parser.parse_args()
    toolchain = args.toolchain.resolve()
    sdk = toolchain / "sdk"
    java = toolchain / "usr/lib/jvm/java-21-openjdk-amd64"
    for required in [sdk / "platform-tools/adb", sdk / "build-tools/35.0.2/apksigner", sdk / "build-tools/35.0.2/zipalign", java / "bin/java", java / "bin/jarsigner", java / "bin/keytool"]:
        if not required.is_file():
            raise SystemExit("Required REAL tool is missing: " + str(required))
    signing = toolchain / "debug-signing"
    signing.mkdir(exist_ok=True)
    keystore = signing / "debug.keystore"
    if not keystore.exists():
        # Standard public Android DEBUG credentials, not production signing data.
        subprocess.run([str(java / "bin/keytool"), "-genkeypair", "-keystore", str(keystore),
                        "-storepass", "android", "-keypass", "android", "-alias", "androiddebugkey",
                        "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000", "-storetype", "JKS",
                        "-dname", "CN=Android Debug,O=Android,C=US"], check=True)
    config = args.config_dir / "godot/editor_settings-4.6.tres"
    config.parent.mkdir(parents=True, exist_ok=True)
    content = config.read_text() if config.exists() else '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
    properties = {
        "export/android/android_sdk_path": str(sdk),
        "export/android/java_sdk_path": str(java),
        "export/android/debug_keystore": str(keystore),
        "export/android/debug_keystore_user": "androiddebugkey",
        "export/android/debug_keystore_pass": "android",
    }
    if "[resource]" not in content:
        raise SystemExit("Unexpected editor settings format; refusing to overwrite it")
    for name, value in properties.items():
        line = name + " = " + json.dumps(value)
        pattern = re.compile(r"^" + re.escape(name) + r"\s*=.*$", re.MULTILINE)
        if pattern.search(content):
            content = pattern.sub(line, content)
        else:
            content = content.rstrip() + "\n" + line + "\n"
    config.write_text(content)
    print("Configured local Godot Android debug profile: " + str(config))
    print("Debug signing only; no Google SDK license acceptance or release signing credentials.")


if __name__ == "__main__":
    main()
