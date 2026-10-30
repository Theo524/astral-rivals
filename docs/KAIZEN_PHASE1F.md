# Phase 1F — recovered body edit and one punch experiment

The interrupted workspace was recovered on 2026-10-30. The playable project is
unchanged. Character data, Blender files, textures, rendered images and baked
motion remain outside this public repository.

## Recovered and checked

- The uploaded VRM and the Phase 1D backup are byte-identical. Neither was edited.
- The original imported Blender file, a separate proportion-edited Blender file,
  the edit report and a separate punch-authoring test file all survived.
- `blender_proportions.py` applies one coordinated mesh/rest-joint edit to an
  existing Z-up humanoid. It does not generate a new character or scale bones.
  The private test compared UVs, weights, shape-key names and material slots:
  they were unchanged. Vertices weighted primarily to head descendants were
  protected and had zero coordinate change. Forearm length and overall height
  were preserved; shoulders and upper arms were widened/lengthened modestly.
- `blender_punch.py` creates a new editable 37-frame Blender Action at 30 FPS.
  Its explicit guard, anticipation, extension and recoil design uses measured
  limb solving and fixed foot anchors. It does not use the game's old punch.
  The recovered test completed on the **original** body; sampled bone matrices
  were finite. This is a scripted first animation pass, not animator-polished
  motion or evidence that the punch looks convincing.

## Initial checkpoint limits

At the recovery checkpoint, the edited body and new punch had not been reviewed together in rendered
front/side motion. Skin weights are unchanged; sleeve deformation is unresolved.
Native Godot reimport, expression checks, neutral before/after renders, contact
verification and animation previews still need completion. No replacement has
been installed in the playable game. No Windows or Android build was made.

## Continued experiment: verified results

After the safe recovery commit, the existing proportion edit was exported once
and the new punch was baked onto that edited body. The tools never loaded the
old game's punch animation. This is an explicit scripted Blender animation
design saved as editable bone keys, **not** a manually polished professional
animation or a licensed motion-capture asset.

The controlled edit changed shoulder-joint span from about 29.8 to 33.8 cm and
upper-arm length from 22.0 to 25.5 cm. Forearm length and stature were retained;
hips moved down about 3 cm to rebalance torso/leg length. Hands were not enlarged.
Face/hair protection, UVs, skin weights, material slots and shape-key names were
checked against the original Blender file. All 24 embedded source images and
57 facial morph targets survived export. Native Godot import and blink passed.

All 37 Blender frames were checked for finite deformed vertex coordinates.
Shoulders, elbows, hips and knees were inspected in the rendered guard,
anticipation, extension and recovery. The lead foot stays planted; the rear
foot pivots. Measured rear-toe drift was about 3 mm, with about 23 mm ankle
movement during the pivot. Wrist-to-middle-knuckle alignment was straight.
A first-pass wrist-frame singularity was found and fixed: the original
backward-to-down palm blend crossed the forearm axis, producing an abrupt hand
flip. Inward-to-down pronation avoids that singularity. Fast recoil still needs
an animator's timing and silhouette review.

`blender_phase1f.py` exports the neutral private model before creating motion,
saves a separate Blender file and writes avatar-derived private motion JSON.
`review_punch.gd` bakes that data into a native Godot `Animation` and plays it
with `AnimationPlayer`. The actual Godot OpenGL renders include:

- Neutral original/edited front, side and three-quarter views.
- Guard, wind-up (0.200 s), impact (0.400 s), recovery (0.600 s).
- A 30 FPS front/side animation sequence for MP4/GIF previews.
- A fixed practice-pad contact fixture, clear at guard and after recovery.

The pad is deliberately calibrated to this character's curled fist at peak
extension, then stays fixed. Visual contact is inspected from the side; the
automated check uses a 2.5 cm knuckle proxy. It is not a live opponent, exact
skin collision or a test of combat damage.

## Sleeve finding and remaining quality limits

The initial Godot renders exposed new dark sleeve gaps and flaring. The edited
mesh has no flipped triangles or extreme triangle-area changes; Blender VRM
roundtrip reproduces the edited sleeve within about a micrometre. Disabling
the imported VRM spring modifiers removes the dark gaps and most flaring in
the rendered comparison. Godot 4.6 drives these through an **internal**
`SkeletonModifier3D`, so disabling ordinary `_process` alone is insufficient.

The clean authored-deformation previews therefore explicitly use
`--freeze-secondary` on **both** original and modified models. They do not
prove that live garment/hair simulation is fixed. Spring rest/collider settings
need retuning for the edited body and rapid motion. Skin weights were not
repainted. Loose-shirt deformation still looks broad; shoe soles penetrate the
reference floor by roughly 6–9 mm in some poses. The casual outfit also hides
much of the improved torso silhouette.

The punch has a new guard, short anticipation, hip/core turn, planted lead foot,
rear-foot pivot, closed fists, extension and recoil. **It remains an animation
first pass.** More manual Blender graph/key-pose work is required for convincing
power, overlap and recovery, followed by garment spring/weight review. There is
no claim that a production-quality anime punch or complete Phase 1F art target
has been achieved. No replacement was installed in the playable game.

Existing game regression suite: **314/314 assertions passed**. The unchanged
game also launched graphically and exited cleanly after 120 frames. Rendering
used Godot 4.6.3 / Xorg / Mesa llvmpipe on Linux with Dummy audio. This does not
verify PC hardware performance, Android or real audio output. No native builds
were made, and no other fighters, scenes, arenas, modes or combat code changed.

## Private outputs and reproduction

The private workspace contains `original.blend`, `proportions.blend`, the
recovered original-body punch test and all diagnostic reports. The latest
authored motion is in `wrist_fix/punch.blend` and `wrist_fix/motion.json`.
`viewer/user_assets/` holds original/edited native scenes and
`straight_punch.res`; `viewer/results/` holds comparison/pose images and frames.
MP4/GIF previews are private derivatives and must not be committed.

To author from an existing private proportion-edited copy:

```sh
blender --background --python tools/vrm_experiment/blender_phase1f.py -- \
  --blend /private/proportions.blend --addon-dir /private/vendor \
  --output /private/new_punch_run
```

Use the Phase 1D pinned Godot importer to convert `modified.vrm` to
`candidate.scn` in the private project. Retain the original native scene as
`original.scn`. Copy `motion.json` into `user_assets/`, and set the private
review scene's script to `review_punch.gd`. With a graphical display:

```sh
godot --path /private/viewer --audio-driver Dummy --fixed-fps 30 -- \
  --capture --freeze-secondary
```

`--stills` omits motion-frame capture. Without `--capture`, the front/side
animation loops interactively; Escape exits. Omit `--freeze-secondary` only to
inspect the unresolved spring behaviour. The public scripts contain no avatar
geometry, images, textures, baked motion or identifying model metadata.

## Recovery boundaries

Private files are under `/workspace/private/kaizen_phase1f/`; the original VRM
also remains in the Phase 1D private directory and original upload. A local
recovery ZIP and checksum manifest preserve these files. This is a workspace
backup, not remote or permanent private hosting. Public Git contains only the
generic tools and this status report, and cannot recover the avatar by itself.

Run the tools only on a **private copy** in Blender with the VRM Addon for Blender
4.10.3 enabled before loading the saved file. `apply_proportions(rig)` refuses a
second pass on an already edited rig. `build(rig)` makes a new Action; retain the
original and save under a new filename. Export the neutral edited VRM before
authoring motion. Do not overwrite the uploaded VRM or commit generated assets.
