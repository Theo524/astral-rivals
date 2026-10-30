"""Controlled, single-pass body adjustment for an existing private humanoid.

Call ``apply_proportions(armature)`` after importing VRM in Blender. The caller
owns saving/exporting to a private copy. No model is generated, no UVs/weights
are replaced, and no object/bone scales are changed. Head descendants are
protected. All absolute shape-key coordinates receive the same body mapping.
"""
import math

import bpy
from mathutils import Vector


def _smooth(a, b, value):
    t = max(0.0, min(1.0, (value-a)/max(b-a, 1e-8)))
    return t*t*(3.0-2.0*t)


def _bone_name(rig, human, fallback):
    try:
        name = getattr(rig.data.vrm_addon_extension.vrm1.humanoid.human_bones,
                       human).node.bone_name
        if name in rig.data.bones:
            return name
    except (AttributeError, KeyError):
        pass
    for name in fallback:
        if name in rig.data.bones:
            return name
    raise ValueError('Required humanoid bone missing: '+human)


def apply_proportions(rig):
    if rig is None or rig.type != 'ARMATURE':
        raise ValueError('Provide the existing imported humanoid armature')
    if rig.get('astral_proportions_applied'):
        raise ValueError('Proportion pass already applied; start from original')
    names = {}
    definitions = {
        'hips': ('Hips','J_Bip_C_Hips'), 'chest': ('Chest','J_Bip_C_Chest'),
        'neck': ('Neck','J_Bip_C_Neck'), 'head': ('Head','J_Bip_C_Head'),
        'left_upper_arm': ('LeftUpperArm','J_Bip_L_UpperArm'),
        'left_lower_arm': ('LeftLowerArm','J_Bip_L_LowerArm'),
        'left_hand': ('LeftHand','J_Bip_L_Hand'),
        'left_lower_leg': ('LeftLowerLeg','J_Bip_L_LowerLeg'),
        'left_foot': ('LeftFoot','J_Bip_L_Foot'),
    }
    for human, fallback in definitions.items():
        names[human] = _bone_name(rig, human, fallback)
    world = rig.matrix_world.copy()
    points = {key: world@rig.data.bones[name].head_local
              for key, name in names.items()}
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH'
              and any(m.type == 'ARMATURE' and m.object == rig for m in obj.modifiers)]
    if not meshes:
        raise ValueError('No meshes skinned to the supplied armature')
    all_points = [obj.matrix_world@v.co for obj in meshes for v in obj.data.vertices]
    top, floor = max(p.z for p in all_points), min(p.z for p in all_points)
    stature = top-floor
    if stature <= 0:
        raise ValueError('Invalid neutral character bounds')
    center_x = points['hips'].x
    shoulder_x = abs(points['left_upper_arm'].x-center_x)
    elbow_x = abs(points['left_lower_arm'].x-center_x)
    if elbow_x <= shoulder_x or shoulder_x <= 0:
        raise ValueError('Expected a neutral Blender Z-up, X-lateral T/A-pose')
    shoulder_z = points['left_upper_arm'].z
    hip_z, neck_z = points['hips'].z, points['neck'].z
    ankle_z = points['left_foot'].z
    shoulder_out = stature*0.0112
    upper_extra = stature*0.0196
    hip_drop = stature*0.0168
    depth_center = points['chest'].y
    arm_center_y = points['left_upper_arm'].y
    head = rig.data.bones[names['head']]
    protected_bones = {head.name} | {b.name for b in head.children_recursive}

    def warp(point):
        p = Vector(point)
        x = p.x-center_x
        ax, z = abs(x), p.z
        # Keep feet fixed and lengthen the torso by lowering the hip/knee
        # region slightly. Head/neck height and overall stature stay fixed.
        arm_band = _smooth(shoulder_z-.18*stature/1.78,
                           shoulder_z-.10*stature/1.78,z)
        arm_band *= 1-_smooth(shoulder_z+.10*stature/1.78,
                              shoulder_z+.16*stature/1.78,z)
        distal = _smooth(shoulder_x,elbow_x,ax)*arm_band
        lower = _smooth(ankle_z+stature*.025,hip_z,z)
        lower *= 1-_smooth(hip_z,neck_z-stature*.017,z)
        p.z -= hip_drop*lower*(1-distal)
        chest = _smooth(hip_z-stature*.01,points['chest'].z,z)
        chest *= 1-_smooth(neck_z-stature*.02,neck_z+stature*.012,z)
        core = ax*0.12*chest
        outer = (shoulder_out+upper_extra*_smooth(shoulder_x,elbow_x,ax))*arm_band
        handoff = _smooth(shoulder_x*.45,shoulder_x,ax)
        offset = core*(1-handoff)+outer*handoff
        p.x += math.copysign(offset,x) if ax > 1e-9 else 0.0
        torso_mask = 1-_smooth(shoulder_x*.75,shoulder_x*1.35,ax)
        p.y = depth_center+(p.y-depth_center)*(1+0.045*chest*torso_mask)
        # A small upper-arm cross-section gain, fading to zero before elbow.
        # Forearms, wrists and hands move outward without changing their shape.
        t = max(0.0,min(1.0,(ax-shoulder_x)/max(elbow_x-shoulder_x,1e-8)))
        bulge = math.sin(t*math.pi)**2*0.065*arm_band if ax < elbow_x else 0.0
        p.y = arm_center_y+(p.y-arm_center_y)*(1+bulge)
        p.z = shoulder_z+(p.z-shoulder_z)*(1+bulge)
        return p

    before = {key: point.copy() for key, point in points.items()}
    bone_coordinates = {bone.name:(bone.head_local.copy(),bone.tail_local.copy())
                        for bone in rig.data.bones}
    head_vertices = 0
    changed_vertices = 0
    max_change = 0.0
    shape_keys = 0
    for obj in meshes:
        to_world = obj.matrix_world.copy()
        to_local = to_world.inverted()
        protected_groups = {g.index for g in obj.vertex_groups if g.name in protected_bones}
        protected = [sum(g.weight for g in v.groups if g.group in protected_groups) >= .5
                     for v in obj.data.vertices]
        head_vertices += sum(protected)
        keys = obj.data.shape_keys.key_blocks if obj.data.shape_keys else None
        # Basis vertices are shared with mesh data: edit every key, or the
        # plain mesh once when it has no keys. Never edit the Basis twice.
        coordinate_sets = [key.data for key in keys] if keys else [obj.data.vertices]
        shape_keys += len(keys) if keys else 0
        for coords in coordinate_sets:
            for i, vertex in enumerate(coords):
                if protected[i]:
                    continue
                original = to_world@vertex.co
                revised = warp(original)
                displacement = (revised-original).length
                max_change = max(max_change,displacement)
                if displacement > 1e-8:
                    changed_vertices += 1
                vertex.co = to_local@revised
        if keys:
            for i, vertex in enumerate(obj.data.vertices):
                vertex.co = keys[0].data[i].co
        obj.data.update()

    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    inverse = world.inverted()
    bpy.ops.object.mode_set(mode='EDIT')
    for bone in rig.data.edit_bones:
        if bone.name in protected_bones:
            continue
        original_head, original_tail = bone_coordinates[bone.name]
        bone.head = inverse@warp(world@original_head)
        bone.tail = inverse@warp(world@original_tail)
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.context.view_layer.update()
    after = {key: world@rig.data.bones[name].head_local for key,name in names.items()}
    rig['astral_proportions_applied'] = True
    return {
        'operation': 'one controlled mesh-and-rest-joint body edit; no bone scaling',
        'stature_unchanged': stature,
        'shoulder_joint_span_before': shoulder_x*2,
        'shoulder_joint_span_after': abs(after['left_upper_arm'].x-center_x)*2,
        'upper_arm_before': (before['left_lower_arm']-before['left_upper_arm']).length,
        'upper_arm_after': (after['left_lower_arm']-after['left_upper_arm']).length,
        'forearm_before': (before['left_hand']-before['left_lower_arm']).length,
        'forearm_after': (after['left_hand']-after['left_lower_arm']).length,
        'hip_height_before': before['hips'].z,
        'hip_height_after': after['hips'].z,
        'neck_height_before': before['neck'].z,
        'neck_height_after': after['neck'].z,
        'protected_head_vertices': head_vertices,
        'shape_key_blocks_preserved': shape_keys,
        'coordinate_edits': changed_vertices,
        'maximum_world_displacement': max_change,
        'uvs_weights_and_materials_unchanged': True,
    }
