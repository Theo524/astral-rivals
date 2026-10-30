"""Export a private neutral VRM copy, author one Action, and bake review motion.

Run with Blender --background --python this_file -- --blend PRIVATE.blend
--addon-dir PRIVATE/vendor --output PRIVATE/new_run. The source must already
contain the single proportion edit. Never writes into the public checkout.
The baked JSON is avatar-derived private data and must not be committed.
"""
import argparse
import json
import math
import sys
from pathlib import Path

import addon_utils
import bpy
from mathutils import Matrix


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--blend', type=Path, required=True)
    parser.add_argument('--addon-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    source, output = args.blend.resolve(), args.output.resolve()
    public = Path(__file__).resolve().parents[2]
    if source.is_relative_to(public) or output.is_relative_to(public) or public.is_relative_to(output):
        raise SystemExit('Model input and output must be outside the public repository')
    if not source.is_file() or source.suffix != '.blend':
        raise SystemExit('Supply the existing private Blender file')
    output.mkdir(parents=True, exist_ok=True)
    if any((output/name).exists() for name in ['modified.vrm', 'punch.blend', 'motion.json']):
        raise SystemExit('Use a new output directory; never overwrite an experiment')
    sys.path.insert(0, str(args.addon_dir.resolve()))
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    addon_utils.enable('VRM_Addon_for_Blender', default_set=True, persistent=False)
    bpy.ops.wm.open_mainfile(filepath=str(source), load_ui=False, use_scripts=False)
    rigs = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE']
    if len(rigs) != 1:
        raise ValueError('Expected exactly one existing humanoid armature')
    rig = rigs[0]
    if rig.animation_data:
        rig.animation_data_clear()
    for bone in rig.pose.bones:
        bone.matrix_basis.identity()
    bpy.context.view_layer.update()
    # Export the neutral model first. Animation is a separate private artifact.
    result = bpy.ops.export_scene.vrm(
        filepath=str(output/'modified.vrm'), use_addon_preferences=False,
        armature_object_name=rig.name, export_invisibles=True,
        export_only_selections=False, export_all_influences=True,
        export_gltf_animations=False)
    if 'FINISHED' not in result or not (output/'modified.vrm').is_file():
        raise RuntimeError('Neutral VRM export failed')
    import blender_punch
    metadata = blender_punch.build(rig)
    names = blender_punch._names(rig, None)
    # Blender Z-up/-Y-forward to Godot Y-up/+Z-forward (a proper rotation).
    conversion = Matrix(((1,0,0),(0,0,1),(0,-1,0)))
    rest = {key: rig.matrix_world @ rig.data.bones[name].matrix_local for key,name in names.items()}
    frames, previous = [], {}
    for frame in range(1, 2+round(metadata['duration']*metadata['fps'])):
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        rotations = {}
        for key, name in names.items():
            posed = rig.matrix_world @ rig.pose.bones[name].matrix
            delta = posed.to_quaternion().to_matrix() @ rest[key].to_quaternion().to_matrix().transposed()
            q = (conversion @ delta @ conversion.transposed()).to_quaternion().normalized()
            if key in previous and previous[key].dot(q) < 0:
                q.negate()
            previous[key] = q.copy()
            rotations[key] = [q.x,q.y,q.z,q.w]
            if not all(math.isfinite(x) for row in posed for x in row):
                raise ValueError('Nonfinite pose at frame '+str(frame))
        hip = rig.matrix_world @ rig.pose.bones[names['hips']].matrix
        translation = conversion @ (hip.translation-rest['hips'].translation)
        frames.append({'time': (frame-1)/metadata['fps'], 'rotations': rotations,
                       'hips_translation': list(translation)})
    metadata['frames'] = frames
    (output/'motion.json').write_text(json.dumps(metadata, separators=(',',':')))
    bpy.context.scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(output/'punch.blend'))
    print('PRIVATE_PUNCH_EXPORT', json.dumps({k:v for k,v in metadata.items() if k!='frames'}))


if __name__ == '__main__':
    main()
