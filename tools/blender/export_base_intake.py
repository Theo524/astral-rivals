"""One isolated intake export of Blender Studio's CC0 stylized male base.

No sculpting, weights, rig or animation is generated. The original .blend and
all game assets remain untouched. Download/source details: docs/KAIZEN_PHASE1B.md.

blender --background --disable-autoexec --python tools/blender/export_base_intake.py \
    -- /path/to/human_base_meshes_bundle.blend /tmp/kaizen-base-intake.glb
"""
import sys
from pathlib import Path

import bpy

MESHES = ('GEO-body_male_stylized', 'GEO-body_male_stylized.eye.L',
          'GEO-body_male_stylized.eye.R')
args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
if len(args) != 2:
    raise SystemExit('Expected -- bundle.blend output.glb')
source, output = map(Path, args)
if output.suffix.lower() != '.glb' or source.resolve() == output.resolve():
    raise SystemExit('Use a separate .glb output outside the game assets')
project = Path(__file__).resolve().parents[2]
if output.resolve().is_relative_to(project):
    raise SystemExit('Intake output must be outside the project; this is not a game asset replacement')
bpy.ops.wm.open_mainfile(filepath=str(source.resolve()), load_ui=False, use_scripts=False)
missing = set(MESHES) - set(bpy.data.objects.keys())
if missing:
    raise SystemExit('Expected official bundle meshes missing: ' + ', '.join(sorted(missing)))
# Append the authored objects into an isolated scene. No other bundle assets,
# example mask drivers, lights or unused anatomical collections are exported.
scene = bpy.data.scenes.new('KaizenBaseIntake')
bpy.context.window.scene = scene
for name in MESHES:
    original = bpy.data.objects[name]
    obj = original.copy()
    obj.data = original.data.copy()
    world = original.matrix_world.copy()
    obj.parent = None
    obj.matrix_world = world
    scene.collection.objects.link(obj)
    obj.hide_viewport = False
    obj.hide_select = False
    obj.hide_set(False)
    obj.hide_render = False
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
if len(bpy.context.selected_objects) != len(MESHES):
    raise SystemExit('Intake selection incomplete; no export attempted')
output.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(output.resolve()), export_format='GLB',
                          use_selection=True, export_animations=False,
                          export_skins=True, export_yup=True)
print('BASE_INTAKE_EXPORTED:', output, '(unrigged original base; not Kaizen)')
