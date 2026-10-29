"""Original authored animation library for the Astral Rivals humanoid rig.

Run from Blender, not ordinary CPython.  Bone rotations are baked into Actions;
there are no Godot limb oscillators or runtime IK dependencies.  The little
two-bone solver below is an *authoring* tool: it gives all keyed poses consistent
limb lengths and lets grounded feet remain planted during body weight shifts.
All animation is in place because CharacterBody3D remains authoritative.
"""
import math
import json
import struct
from copy import deepcopy
from pathlib import Path

import bpy
from mathutils import Vector, Quaternion, Euler

FPS = 30
ORIGIN = Vector((0.0, 0.0, 1.02))
CLIPS = {
    "idle": (2.4, True), "walk": (0.96, True), "run": (0.62, True),
    "hover": (2.0, True), "fly": (0.8, True),
    "dash_forward": (0.24, False), "dash_back": (0.24, False),
    "punch_1": (0.34, False), "punch_2": (0.34, False),
    "punch_3": (0.34, False), "kick": (0.5, False),
    "heavy": (0.64, False), "blast": (0.38, False),
    "beam": (1.6, False), "charge": (1.6, True), "guard": (1.2, True),
    "parry": (0.3, False), "dodge": (0.24, False), "hurt": (0.35, False),
    "knockback": (0.65, False), "recovery": (0.5, False),
    "transform": (1.3, False), "ultimate": (2.6, False),
    "victory": (2.0, True), "defeat": (1.2, False),
}


def _smooth(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3.0 - 2.0 * t)


def _mix(a, b, t):
    if isinstance(a, (tuple, list)):
        return tuple(_mix(x, y, t) for x, y in zip(a, b))
    if isinstance(a, dict):
        return {key: _mix(a[key], b[key], t) for key in a}
    if isinstance(a, bool):
        return b if t >= 0.5 else a
    return a + (b - a) * t


def _over(base, **changes):
    pose = deepcopy(base)
    pose.update(changes)
    return pose


def _keys(keys, t):
    if t <= keys[0][0]:
        return deepcopy(keys[0][1])
    for i in range(1, len(keys)):
        if t <= keys[i][0]:
            a, pa = keys[i - 1]
            b, pb = keys[i]
            return _mix(pa, pb, _smooth((t - a) / max(b - a, 0.00001)))
    return deepcopy(keys[-1][1])


def _stance(identity):
    # Deliberately different center of gravity and guard/silhouette per warrior.
    low = {"kaizen": -0.055, "ryuzen": -0.11, "akira": -0.025}[identity]
    lead = {"kaizen": -0.23, "ryuzen": -0.29, "akira": -0.17}[identity]
    return {
        "hips": (0.0, -0.015, low), "body": (0.0, 0.0, 0.0),
        "torso": (0.06, 0.0, -0.09 if identity != "akira" else 0.045),
        "head": (-0.025, 0.0, 0.035),
        "wrist_l": (0.25, -0.37, 1.54 if identity != "akira" else 1.48),
        "wrist_r": (-0.24, -0.23, 1.49 if identity != "ryuzen" else 1.43),
        "elbow_l": (0.50, -0.04, 1.29), "elbow_r": (-0.46, 0.02, 1.25),
        "ankle_l": (0.16, lead, 0.16), "ankle_r": (-0.17, 0.18, 0.16),
        "foot_l": (0.0, 0.0, -0.06), "foot_r": (0.0, 0.0, 0.12),
        "follow_feet": False,
    }


def _pose(clip, t, identity):
    p = _stance(identity)
    tau = math.tau
    if clip == "idle":
        b = math.sin(t * tau)
        p["hips"] = (0.008 * b, -0.015, p["hips"][2] + 0.008 * b)
        p["torso"] = (0.06 + 0.012 * b, 0.0, p["torso"][2])
        p["wrist_l"] = (0.25, -0.37, p["wrist_l"][2] + 0.01 * b)
        p["wrist_r"] = (-0.24, -0.23, p["wrist_r"][2] - 0.006 * b)
        return p
    if clip in ("walk", "run"):
        fast = clip == "run"
        a = t * tau
        stride = 0.37 if fast else 0.23
        lift = 0.25 if fast else 0.09
        p["hips"] = (0.018 * math.sin(a), -0.05 if fast else 0.0,
                     -0.11 + abs(math.sin(a)) * 0.022 if fast else -0.065 + abs(math.sin(a)) * 0.012)
        p["torso"] = (0.22 if fast else 0.07, 0.0, 0.07 * math.sin(a))
        for side, phase in (("l", a), ("r", a + math.pi)):
            s = 1.0 if side == "l" else -1.0
            p["ankle_" + side] = (s * 0.145, -math.cos(phase) * stride,
                                      0.16 + max(0.0, math.sin(phase)) * lift)
            p["wrist_" + side] = (s * 0.31, math.cos(phase) * (0.29 if fast else 0.13), 1.29 if fast else 1.2)
            p["elbow_" + side] = (s * 0.43, math.cos(phase) * 0.12 + 0.12, 1.36)
            p["foot_" + side] = (max(0.0, math.sin(phase)) * -0.35, 0.0, s * -0.035)
        return p
    if clip in ("hover", "fly", "dash_forward", "dash_back"):
        flight = clip != "hover"
        phase = math.sin(t * tau)
        lean = 0.58 if flight else 0.045
        if clip == "dash_back":
            lean = -0.28
        p["body"] = (lean, 0.0, 0.0)
        p["hips"] = (0.0, 0.0, 0.045 + phase * 0.018)
        p["ankle_l"] = (0.20, 0.02, 0.33)
        p["ankle_r"] = (-0.19, 0.26, 0.46)
        p["follow_feet"] = True
        if flight:
            p["wrist_l"] = (0.42, 0.22, 1.15)
            p["wrist_r"] = (-0.41, 0.26, 1.14)
            p["elbow_l"] = (0.54, 0.20, 1.38)
            p["elbow_r"] = (-0.54, 0.21, 1.38)
            p["head"] = (-0.43, 0.0, 0.0)
        return p
    if clip in ("punch_1", "punch_2", "punch_3"):
        side = "r" if clip == "punch_2" else "l"
        s = -1.0 if side == "r" else 1.0
        wind = _over(p, torso=(0.03, 0.0, -s * 0.25), hips=(-s * 0.025, 0.035, p["hips"][2]-0.015))
        wind["wrist_" + side] = (s * 0.28, -0.06, 1.47)
        reach = 0.60 if clip != "punch_3" else 0.56
        hit = _over(p, torso=(0.13, -s * 0.025, s * 0.30), hips=(s * 0.025, -0.055, p["hips"][2]))
        hit["wrist_" + side] = (s * 0.15, -reach, 1.54 if clip != "punch_3" else 1.71)
        hit["elbow_" + side] = (s * 0.20, -0.28, 1.38)
        if clip == "punch_3":
            wind["wrist_l"] = (0.30, -0.14, 1.27)
            hit["torso"] = (-0.05, -0.06, 0.28)
        follow = deepcopy(hit)
        follow["wrist_" + side] = (s * 0.09, -0.57, 1.55)
        return _keys([(0, p), (.20, wind), (.41, hit), (.58, follow), (1, p)], t)
    if clip in ("kick", "heavy"):
        heavy = clip == "heavy"
        wind = _over(p, hips=(-0.035, 0.02, -0.13), torso=(0.08, 0.0, -0.28))
        wind["ankle_r"] = (-0.25, 0.10, 0.56)
        wind["follow_feet"] = True
        hit = _over(p, hips=(-0.045, -0.015, -0.035), torso=(-0.12, 0.16, 0.38))
        hit["ankle_r"] = (-0.10, -0.72 if heavy else -0.70, 1.09 if heavy else 1.31)
        hit["ankle_l"] = (0.18, 0.04, 0.16)
        hit["wrist_l"] = (0.34, -0.16, 1.62)
        hit["wrist_r"] = (-0.46, 0.16, 1.36)
        hit["foot_r"] = (-0.35, 0.0, 0.0)
        hit["follow_feet"] = True
        recoil = deepcopy(hit)
        recoil["ankle_r"] = (-0.26, -0.27, 0.68)
        recoil["torso"] = (0.0, 0.02, 0.12)
        return _keys([(0,p),(.24,wind),(.44 if heavy else .41,hit),(.67,recoil),(1,p)],t)
    if clip in ("blast", "beam", "ultimate"):
        two = clip != "blast"
        wind = _over(p, torso=(0.02,0.0,-0.25), hips=(0.0,0.015,-0.075))
        wind["wrist_l"] = (0.17,-0.08,1.27)
        wind["wrist_r"] = (-0.13,-0.04,1.30)
        wind["elbow_l"] = (0.47,0.16,1.38)
        wind["elbow_r"] = (-0.44,0.12,1.39)
        fire = _over(p, torso=(0.10,0.0,0.06), hips=(0.0,0.06,-0.09))
        fire["wrist_l"] = (0.15,-0.62,1.46)
        fire["wrist_r"] = (-0.15,-0.60,1.46) if two else p["wrist_r"]
        fire["elbow_l"] = (0.23,-0.24,1.41)
        fire["elbow_r"] = (-0.23,-0.24,1.41)
        release = .20 if clip == "beam" else (.20 if clip == "ultimate" else .41)
        if clip == "ultimate":
            wind["wrist_l"] = (0.22,-0.02,1.81)
            wind["wrist_r"] = (-0.22,-0.02,1.81)
            wind["torso"] = (-0.08,0.0,0.0)
        return _keys([(0,p),(release*.65,wind),(release,fire),(.84,fire),(1,p)],t)
    if clip in ("charge","transform"):
        charged = _over(p, hips=(0.0,0.0,-0.11), torso=(-0.045,0.0,0.0),
                        wrist_l=(0.35,-0.20,1.15),wrist_r=(-0.35,-0.20,1.15),
                        elbow_l=(0.48,0.02,1.38),elbow_r=(-0.48,0.02,1.38),head=(-0.07,0.0,0.0))
        if clip == "charge":
            b = math.sin(t*tau)
            charged["hips"] = (0.002*b,0.0,-0.11+0.008*b)
            charged["wrist_l"] = (0.35,-0.20,1.15+0.009*b)
            charged["wrist_r"] = (-0.35,-0.20,1.15-0.009*b)
            return charged
        peak = _over(charged, hips=(0.0,0.0,-0.035),torso=(-0.10,0.0,0.0),
                     wrist_l=(0.45,-0.08,1.22),wrist_r=(-0.45,-0.08,1.22),head=(-0.11,0.0,0.0))
        return _keys([(0,p),(.3,charged),(.62,charged),(.74,peak),(1,p)],t)
    if clip in ("guard","parry"):
        guard = _over(p, hips=(0.0,0.0,-0.10),torso=(0.15,0.0,0.0),head=(0.02,0.0,0.0),
                      wrist_l=(0.17,-0.31,1.70),wrist_r=(-0.17,-0.30,1.67),
                      elbow_l=(0.28,-0.21,1.29),elbow_r=(-0.28,-0.19,1.29))
        if clip == "guard":
            guard["hips"] = (0.004*math.sin(t*tau),0.0,-0.10)
            return guard
        deflect = _over(guard,wrist_l=(0.37,-0.46,1.67),torso=(0.11,0.0,0.15))
        return _keys([(0,guard),(.32,deflect),(.6,guard),(1,p)],t)
    if clip == "dodge":
        duck = _over(p, hips=(0.15,0.02,-0.22),torso=(0.20,-0.24,0.28),head=(-0.10,0.05,0.0),
                     wrist_l=(0.22,-0.15,1.52),wrist_r=(-0.20,-0.04,1.48))
        return _keys([(0,p),(.35,duck),(.65,duck),(1,p)],t)
    if clip in ("hurt","knockback","recovery"):
        struck = _over(p, hips=(0.0,0.05,-0.08),torso=(-0.31,0.02,0.13),head=(-0.14,0.0,0.0),
                       wrist_l=(0.36,0.01,1.48),wrist_r=(-0.40,0.03,1.40))
        if clip == "knockback":
            struck.update(body=(-0.30,0.0,0.0),ankle_l=(.22,.05,.35),ankle_r=(-.22,.20,.42),follow_feet=True)
            return _keys([(0,p),(.16,struck),(.84,struck),(1,p)],t)
        if clip == "recovery":
            tuck = _over(p,hips=(0.0,0.02,-.20),torso=(.22,0.0,0.0))
            return _keys([(0,struck),(.30,tuck),(1,p)],t)
        return _keys([(0,p),(.13,struck),(.43,struck),(1,p)],t)
    if clip == "victory":
        b = math.sin(t*tau)
        p.update(torso=(-0.015,0.0,0.0),head=(-.04,0.0,-.08),
                 wrist_l=(.31,-.02,2.03+0.01*b),elbow_l=(.44,.0,1.84),
                 wrist_r=(-.30,-.06,1.16),elbow_r=(-.43,.05,1.30))
        return p
    if clip == "defeat":
        down = _over(p,hips=(0.0,0.0,-.77),body=(0.0,-1.48,0.0),torso=(0.0,0.0,0.0),head=(.03,0.0,.08),
                     wrist_l=(.48,-.05,1.14),wrist_r=(-.40,-.10,1.23),
                     ankle_l=(.19,-.05,.18),ankle_r=(-.22,.20,.25),follow_feet=True)
        return _keys([(0,p),(.28,_over(p,torso=(-.22,0.0,.15))),(.78,down),(1,down)],t)
    return p


def _local_axis_rotation(pb, xyz):
    rest = pb.bone.matrix_local.to_quaternion()
    world = Euler(xyz,"XYZ").to_quaternion()
    pb.rotation_quaternion = rest.inverted() @ world @ rest


def _orient(armature, name, direction, twist=0.0):
    pb = armature.pose.bones[name]
    rest = pb.bone.matrix_local.to_quaternion()
    direction = Vector(direction).normalized()
    original = (pb.bone.tail_local-pb.bone.head_local).normalized()
    desired = original.rotation_difference(direction) @ rest
    if abs(twist)>0.00001:
        desired = Quaternion(direction,twist) @ desired
    if pb.parent:
        local_rest = pb.parent.bone.matrix_local.to_quaternion().inverted() @ rest
        desired_local = pb.parent.matrix.to_quaternion().inverted() @ desired
        pb.rotation_quaternion = local_rest.inverted() @ desired_local
    else:
        pb.rotation_quaternion = rest.inverted() @ desired
    bpy.context.view_layer.update()


def _two_bone(armature, upper_name, lower_name, target, hint):
    upper = armature.pose.bones[upper_name]
    lower = armature.pose.bones[lower_name]
    start = upper.head.copy()
    target = Vector(target)
    aim = target-start
    distance = aim.length
    if distance<0.00001:
        aim = Vector((0,-1,0)); distance=.00001
    aim.normalize()
    l1,l2 = upper.bone.length,lower.bone.length
    distance = min(l1+l2-.0005,max(abs(l1-l2)+.0005,distance))
    along=(l1*l1-l2*l2+distance*distance)/(2.0*distance)
    height=math.sqrt(max(0.0,l1*l1-along*along))
    plane=Vector(hint)-start
    plane-=aim*plane.dot(aim)
    if plane.length_squared<.00001:
        plane=aim.cross(Vector((0,0,1)))
    if plane.length_squared<.00001:
        plane=Vector((1,0,0))
    plane.normalize()
    elbow=start+aim*along+plane*height
    end=start+aim*distance
    _orient(armature,upper_name,elbow-start)
    _orient(armature,lower_name,end-armature.pose.bones[lower_name].head)


def _apply(armature, pose, frame, previous=None):
    bones=armature.pose.bones
    for pb in bones:
        pb.rotation_mode="QUATERNION"
        pb.rotation_quaternion=Quaternion()
        pb.location=(0,0,0)
        pb.scale=(1,1,1)
    rotation=Euler(pose["body"],"XYZ").to_quaternion()
    shift=Vector(pose["hips"])
    hips=bones["hips"]
    hips.location=hips.bone.matrix_local.to_quaternion().inverted() @ shift
    _local_axis_rotation(hips,pose["body"])
    torso=Vector(pose["torso"])
    _local_axis_rotation(bones["spine"],tuple(torso*.46))
    _local_axis_rotation(bones["chest"],tuple(torso*.54))
    _local_axis_rotation(bones["neck"],tuple(Vector(pose["head"])*.35))
    _local_axis_rotation(bones["head"],tuple(Vector(pose["head"])*.65))
    bpy.context.view_layer.update()
    def transform(point,follow=True):
        return rotation @ (Vector(point)-ORIGIN)+ORIGIN+(shift if follow else Vector())
    for side in ("L","R"):
        key=side.lower(); s=1.0 if side=="L" else -1.0
        wrist=transform(pose["wrist_"+key])
        elbow=transform(pose["elbow_"+key])
        _two_bone(armature,"upper_arm."+side,"forearm."+side,wrist,elbow)
        # Fists maintain the forearm direction; no detached wrist flicking.
        bones["hand."+side].rotation_quaternion=Quaternion()
        ankle=transform(pose["ankle_"+key]) if pose["follow_feet"] else Vector(pose["ankle_"+key])
        knee=transform((s*.16,-.24,.65))
        _two_bone(armature,"thigh."+side,"shin."+side,ankle,knee)
        # Resolve the foot independently of shin rotation: the sole stays level
        # on contact frames instead of rotating like a rigid lower-leg stick.
        foot=bones["foot."+side]
        original=(foot.bone.tail_local-foot.bone.head_local).normalized()
        desired=Euler(pose["foot_"+key],"XYZ").to_quaternion() @ original
        if pose["follow_feet"]:
            desired=rotation @ desired
        _orient(armature,"foot."+side,desired)
    for pb in bones:
        # q and -q describe the same rotation, but component animation curves
        # must stay in one hemisphere. Otherwise Blender's interpolation can
        # cross the zero quaternion and visibly snap a shoulder/elbow.
        if previous is not None:
            value=pb.rotation_quaternion.copy()
            if pb.name in previous and previous[pb.name].dot(value)<0.0:
                value.negate()
                pb.rotation_quaternion=value
            previous[pb.name]=value.copy()
        pb.keyframe_insert("rotation_quaternion",frame=frame,group=pb.name)
        if pb.name in ("root","hips"):
            pb.keyframe_insert("location",frame=frame,group=pb.name)


def build_animations(armature, identity="kaizen"):
    """Create and attach all original Actions, returning JSON-safe metadata.

    Export with export_animation_mode='ACTIONS', export_frame_range=False,
    export_force_sampling=True. Every action is also placed in one named NLA
    track for Blender inspection / alternative NLA export workflows.
    """
    identity=identity if identity in ("kaizen","ryuzen","akira") else "kaizen"
    bpy.context.scene.render.fps=FPS
    bpy.context.view_layer.objects.active=armature
    armature.select_set(True)
    if not armature.animation_data:
        armature.animation_data_create()
    armature.animation_data.action=None
    for track in list(armature.animation_data.nla_tracks):
        armature.animation_data.nla_tracks.remove(track)
    metadata={"fps":FPS,"identity":identity,"clips":{}}
    for name,(seconds,loop) in CLIPS.items():
        action=bpy.data.actions.new(name=name)
        action.use_fake_user=True
        armature.animation_data.action=action
        frames=max(2,round(seconds*FPS))
        previous={}
        for step in range(frames+1):
            _apply(armature,_pose(name,step/frames,identity),step+1,previous)
        for fc in action.fcurves:
            # Dense authored pose sampling is smoothstep before baking. LINEAR
            # avoids Bezier overshoot through knees and quaternion components.
            for key in fc.keyframe_points:
                key.interpolation="LINEAR"
        action["loop"]=loop
        action["authorship"]="Original Astral Rivals keyed skeletal motion"
        track=armature.animation_data.nla_tracks.new()
        track.name=name
        strip=track.strips.new(name,1,action)
        strip.action_frame_start=1
        strip.action_frame_end=frames+1
        strip.extrapolation="NOTHING"
        strip.blend_type="REPLACE"
        track.mute=True
        metadata["clips"][name]={"duration":frames/FPS,"loop":loop,"frames":frames+1}
        if name in ("punch_1","punch_2","punch_3","kick","heavy"):
            metadata["clips"][name]["contact_normalized"]=.44 if name=="heavy" else .41
    armature.animation_data.action=None
    for pb in armature.pose.bones:
        pb.rotation_quaternion=Quaternion()
        pb.location=(0,0,0)
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    return metadata


def normalize_glb_quaternions(filepath):
    """Keep exported rotation samples in the same quaternion hemisphere.

    Blender's GLB exporter decomposes sampled matrices again, independently of
    the continuous authored key values. q and -q remain the same pose, but
    making the binary samples continuous also protects simple GLTF consumers
    from interpolating through zero. Only four float components change; the
    file structure, bind pose, clip length and every actual pose are preserved.
    """
    path=Path(filepath)
    data=bytearray(path.read_bytes())
    if data[:4]!=b"glTF":
        raise ValueError("Expected binary GLTF 2.0")
    json_size,kind=struct.unpack_from("<II",data,12)
    if kind!=0x4E4F534A:
        raise ValueError("Missing GLB JSON chunk")
    document=json.loads(data[20:20+json_size])
    binary_header=20+json_size
    _,binary_kind=struct.unpack_from("<II",data,binary_header)
    if binary_kind!=0x004E4942:
        raise ValueError("Missing GLB binary chunk")
    binary_start=binary_header+8
    processed=set()
    corrections=0
    for clip in document.get("animations",[]):
        for channel in clip.get("channels",[]):
            if channel["target"].get("path")!="rotation":
                continue
            sampler=clip["samplers"][channel["sampler"]]
            index=sampler["output"]
            if index in processed:
                continue
            processed.add(index)
            accessor=document["accessors"][index]
            if accessor["type"]!="VEC4" or accessor["componentType"]!=5126:
                raise ValueError("Rotation samples must be float32 quaternions")
            if sampler.get("interpolation","LINEAR")=="CUBICSPLINE":
                raise ValueError("Bake authored rotations to LINEAR before export")
            view=document["bufferViews"][accessor["bufferView"]]
            offset=binary_start+view.get("byteOffset",0)+accessor.get("byteOffset",0)
            stride=view.get("byteStride",16)
            previous=None
            for frame in range(accessor["count"]):
                cursor=offset+frame*stride
                value=struct.unpack_from("<4f",data,cursor)
                if previous is not None and sum(a*b for a,b in zip(previous,value))<0.0:
                    value=tuple(-v for v in value)
                    struct.pack_into("<4f",data,cursor,*value)
                    corrections+=1
                previous=value
    path.write_bytes(data)
    return corrections
