"""Render the existing authored Blender assets without rebuilding or exporting.

Run with Blender background mode. These CPU Cycles images inspect geometry and
skeletal poses; they are not screenshots of Godot or native-device validation.
"""
import bpy
import math
import sys
from mathutils import Vector
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]
SOURCE = PROJECT / "tools/blender/source"
OUTPUT = PROJECT / "docs/review"
OUTPUT.mkdir(parents=True, exist_ok=True)
(OUTPUT / ".gdignore").touch()


def render(identity, clip, phase, filename):
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE / (identity + ".blend")))
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 20
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 640
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.world.color = (0.045, 0.055, 0.085)
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "Medium High Contrast"
    # White/gold cloth must retain detail in this studio review rather than
    # clipping under the three broad area lights. This is a review-camera
    # exposure choice, not a change to Godot materials or the game assets.
    scene.view_settings.exposure = -0.75
    rig = bpy.data.objects["AstralRig"]
    action = bpy.data.actions[clip]
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    rig.animation_data.action = action
    start, end = action.frame_range
    frame = start + (end - start) * phase
    scene.frame_set(math.floor(frame), subframe=frame - math.floor(frame))
    bpy.context.view_layer.update()

    cam_data = bpy.data.cameras.new("ReviewCamera")
    camera = bpy.data.objects.new("ReviewCamera", cam_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (3.15, -5.8, 2.6)
    target = Vector((0, 0, 1.2))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.72
    scene.camera = camera

    for name, position, power, size, color in [
        ("Key", (-3, -4, 5), 650, 4, (0.85, 0.92, 1)),
        ("Fill", (3, -2, 3), 450, 3, (1, 0.78, 0.57)),
        ("Rim", (1, 3, 4), 950, 3, (0.46, 0.72, 1)),
    ]:
        data = bpy.data.lights.new(name, "AREA")
        data.energy = power
        data.shape = "DISK"
        data.size = size
        data.color = color
        light = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(light)
        light.location = position
        light.rotation_euler = (target - light.location).to_track_quat("-Z", "Y").to_euler()
    floor_data = bpy.data.meshes.new("ReviewFloor")
    floor_data.from_pydata([(-200, -200, 0), (200, -200, 0), (200, 200, 0), (-200, 200, 0)], [], [(0, 1, 2, 3)])
    floor = bpy.data.objects.new("ReviewFloor", floor_data)
    bpy.context.collection.objects.link(floor)
    floor.location.z = -0.002
    material = bpy.data.materials.new("ReviewFloor")
    material.diffuse_color = (0.025, 0.035, 0.055, 1)
    material.use_nodes = True
    material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = material.diffuse_color
    floor.data.materials.append(material)
    scene.render.filepath = str(OUTPUT / filename)
    bpy.ops.render.render(write_still=True)
    print("REVIEW_COMPLETE", identity, clip, phase, scene.render.filepath)


TASKS = [
    ("ryuzen", "idle", 0.0, "ryuzen_idle.png"),
    ("akira", "idle", 0.0, "akira_idle.png"),
    ("kaizen", "punch_1", 0.41, "kaizen_punch_contact.png"),
    ("kaizen", "kick", 0.41, "kaizen_kick_contact.png"),
    ("kaizen", "beam", 0.5, "kaizen_beam_pose.png"),
]

if __name__ == "__main__":
    selected = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for identity, clip, phase, filename in TASKS:
        if not selected or identity in selected:
            render(identity, clip, phase, filename)
