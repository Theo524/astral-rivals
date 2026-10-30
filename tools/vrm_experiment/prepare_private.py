"""Create an isolated VRM 1.0 experiment; never put user assets in this repo.

python3 tools/vrm_experiment/prepare_private.py --vrm /private/kaizen.vrm \
    --output /workspace/private/kaizen_phase1e
Only the pinned MIT importer is downloaded. No user data is uploaded.
"""
import argparse
import hashlib
import json
import shutil
import struct
import urllib.request
import zipfile
from pathlib import Path

PIN = 'e15199f980064028bfa4fbee5e70dddb82dd55c3'
PROJECT = Path(__file__).resolve().parents[2]
SCRIPT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--vrm', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
source, output = args.vrm.resolve(), args.output.resolve()
if not source.is_file() or source.suffix.lower() != '.vrm':
    raise SystemExit('Supply an existing VRM file')
if output.is_relative_to(PROJECT) or PROJECT.is_relative_to(output) or source.is_relative_to(PROJECT):
    raise SystemExit('Input and experiment output must be outside the public repository')
content = source.read_bytes()
if len(content) < 20 or struct.unpack_from('<III', content) != (0x46546C67, 2, len(content)):
    raise SystemExit('Expected a valid VRM/glTF 2 binary container')
size, kind = struct.unpack_from('<II', content, 12)
if kind != 0x4E4F534A or 20 + size > len(content):
    raise SystemExit('Invalid VRM JSON chunk')
gltf = json.loads(content[20:20+size])
vrm = gltf.get('extensions', {}).get('VRMC_vrm', {})
if vrm.get('specVersion') != '1.0':
    raise SystemExit('This focused experiment requires VRM 1.0')
manifest = {
    'source_sha256': hashlib.sha256(content).hexdigest(),
    'morph_targets': sum(max((len(p.get('targets', [])) for p in m.get('primitives', [])), default=0)
                         for m in gltf.get('meshes', [])),
    'expressions': list(vrm.get('expressions', {}).get('preset', {})) +
                   list(vrm.get('expressions', {}).get('custom', {})),
}
output.mkdir(parents=True, exist_ok=True)
archive = output / 'godot-vrm.zip'
if not archive.exists():
    url = 'https://codeload.github.com/V-Sekai/godot-vrm/zip/' + PIN
    with urllib.request.urlopen(url, timeout=40) as response, archive.open('wb') as file:
        shutil.copyfileobj(response, file)
with zipfile.ZipFile(archive) as bundle:
    for item in bundle.infolist():
        parts = Path(item.filename).parts
        if not parts or parts[0] != 'godot-vrm-' + PIN:
            raise SystemExit('Cached importer archive does not match the pinned revision')
        relative = Path(*parts[1:])
        if item.is_dir() or not relative.parts:
            continue
        if '..' in relative.parts:
            raise SystemExit('Unsafe importer archive path')
        if relative.parts[0] == 'addons' or str(relative) == 'LICENSE':
            target = output / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(bundle.read(item))
for folder in ['user_assets', 'reference', 'experiment', 'results']:
    (output / folder).mkdir(exist_ok=True)
(output / 'user_assets/.gdignore').touch()
(output / 'results/.gdignore').touch()
if source != output / 'user_assets/kaizen.vrm':
    shutil.copy2(source, output / 'user_assets/kaizen.vrm')
(output / 'user_assets/source_manifest.json').write_text(json.dumps(manifest, indent=2))
shutil.copy2(PROJECT / 'assets/characters/kaizen.glb', output / 'reference/source_kaizen.glb')
for name in ['import_vrm.gd', 'humanoid_retarget.gd', 'martial_pose.gd', 'finger_pose.gd', 'review.gd']:
    file = SCRIPT / name
    shutil.copy2(file, output / 'experiment' / file.name)
(output / 'project.godot').write_text('''config_version=5
[application]
config/name="Kaizen Private VRM Experiment"
run/main_scene="res://experiment/review.tscn"
[display]
window/size/viewport_width=1000
window/size/viewport_height=900
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
anti_aliasing/quality/msaa_3d=1
[editor_plugins]
enabled=PackedStringArray("res://addons/vrm/plugin.cfg", "res://addons/Godot-MToon-Shader/plugin.cfg")
''')
(output / 'experiment/review.tscn').write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://experiment/review.gd" id="1"]
[node name="PrivateReview" type="Node3D"]
script = ExtResource("1")
''')
print('Private project prepared outside the public source tree:', output)
print('Importer code:', PIN, '(MIT); user assets remain private')
