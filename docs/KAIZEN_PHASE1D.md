# Phase 1D — private VRM 1.0 integration experiment

Historical result at `0d6c833`. The current review tools now include
[Phase 1E pose corrections](KAIZEN_PHASE1E.md); use that document for the latest
idle, walk, fist and punch inspection behavior.

2026-10-30, starting from `81d9318`. This milestone integrates the user's actual
VRoid file in a **separate private Godot project**. The public playable Kaizen,
other fighters, combat, input and game modes remain unchanged. No native
packages were rebuilt.

## Successful work

- Read the actual VRM 1.0 file and used a compatible VRM importer, rather than
  treating it as ordinary glTF and discarding the VRM extensions.
- Preserved the supplied textured appearance and hair using the importer's
  MToon shaders. The game's existing toon-material replacement is not applied.
- Retained the humanoid, finger/face joints and source morph targets. Humanoid
  names/rest frames are normalized by the importer; the skeleton is not
  represented as a byte-identical copy of the source.
- Preserved the expression animation library and tested blink driving actual
  facial blend shapes. Required source expression names and morph counts are
  checked against a **private** source manifest before accepting conversion.
- Saved a native Godot `PackedScene` and loaded it again in the private viewer.
  Skin binds are checked against the converted skeleton before saving.
- Mapped the existing Kaizen body animation skeleton onto the VRM humanoid,
  correcting A/T rest-pose and bone-axis differences. Extra finger/face bones
  are not overwritten by this mapping.
- Tested **only idle, walk and punch_1**, at five sample times each, and
  rendered those poses. The viewer transfers motion at runtime from the public
  source clips; it does not bake or replace the fighter's animation asset.
- Captured private Godot full-body and close-up images, plus walk/punch
  inspection images. These are actual OpenGL output, not concept art.

## Importer and compatibility details

The MIT-licensed [V-Sekai/godot-vrm importer](https://github.com/V-Sekai/godot-vrm)
is pinned to `e15199f980064028bfa4fbee5e70dddb82dd55c3`. Both `addons/vrm` and
`addons/Godot-MToon-Shader` are installed in the private project. The bootstrap
downloads only that code archive; it does not upload the user's model.

Two integration details are necessary on the tested Godot 4.6.3 build:

1. Register VRM extensions with first priority, in reverse registration order,
   so humanoid processing runs before spring bones and before Godot's built-in
   importer-mesh conversion. Incorrect ordering reproducibly left stale mesh
   node references, broken skin names and incomplete expression creation.
2. Seed the `vrm/already_processed` additional-data key with NIL before import.
   The upstream initial lookup otherwise triggers a Godot missing-key error.

The final import and native-scene reload run without those errors. Head hiding
is disabled for inspection. Original MToon materials are retained, and conversion
uses a native scene; the upstream VRM/glTF exporter is not used.

## Reproduce without publishing the avatar

Use Godot **4.6.3 Standard** and Python 3.9+. Keep input/output outside the
public checkout. Substitute your own private paths:

```sh
python3 tools/vrm_experiment/prepare_private.py \
  --vrm /path/to/private/kaizen.vrm \
  --output /path/outside/repository/kaizen_private

godot --headless --editor --path /path/outside/repository/kaizen_private --import

godot --headless --path /path/outside/repository/kaizen_private \
  --script res://experiment/import_vrm.gd

godot --headless --path /path/outside/repository/kaizen_private

godot --path /path/outside/repository/kaizen_private
```

The initial editor-import step registers addon classes and imports the public
reference animation asset. It is required for a fresh private project. The
viewer uses **1 = idle, 2 = walk, 3 = punch, Tab = camera, Esc = quit**.

For actual graphical captures, run the private project on a working display:

```sh
godot --path /path/outside/repository/kaizen_private \
  --audio-driver Dummy --fixed-fps 60 -- --capture
```

`--capture` explicitly rejects headless mode. Screenshots go to that private
project's `results/full_body.png`, `close_up.png`, `walk.png` and `punch_1.png`.
The converted native asset is `user_assets/candidate.scn`; the original upload
is retained as `user_assets/kaizen.vrm`. Neither belongs in this repository.
Managed Linux sessions may need writable XDG directories and a valid `DISPLAY`.

## Verification and privacy

- Final private VRM import: successful, required expressions/morphs retained,
  no invalid named skin binds, textured shader surfaces present.
- Native scene reload: successful, blink changes facial morph values,
  requested clips produce finite poses and unmapped finger poses are retained.
- Actual graphical inspection: Linux Xorg / Mesa llvmpipe OpenGL Compatibility;
  full-body, close-up, walk and punch captures saved privately. The software
  driver warns that changing V-Sync mode is unsupported.
- Public mathematical regression: nine poses across the same three clips,
  using the existing public Kaizen and a synthetic T-pose skeleton. Limb
  direction transfer and untouched extra finger pose pass. This test is not
  evidence of visual quality on the user's avatar.
- Existing game: **314/314 regression checks passed**. Public project editor
  import and Python syntax checks also pass.

Run the public tests independently:

```sh
./tools/check.sh
godot --headless --path . --script res://tools/vrm_experiment/retarget_test.gd
```

Only generic code, script identifiers, privacy ignore rules and this sanitized
documentation are committed. **No VRM, native/derived model, texture, avatar
metadata/manifest, private log, report or screenshot is committed.** The
bootstrap rejects inputs/outputs inside the public repository and copies only
the required runtime scripts into the private project. VRM/VROID files and
private-folder conventions are also ignored by Git. No external hosting or
public image upload was used.

## Remaining problems and stopping point

The model imports and animates in the isolated viewer, but is **not yet a
verified playable replacement**:

- The old clips have no finger animation. Finger joints survive, but the
  retargeted punch keeps open fingers instead of forming a fist.
- Some sleeve/arm clipping is visible during walking. The transferred guard
  and wrist presentation need adjustment for the new proportions and clothing.
- Foot planting/root-motion fitting, hitbox contact, animation blending and
  in-game camera behavior have not been validated on this model.
- Only blink was exercised as a facial expression; the other expression
  clips are preserved, not all visually tested. There is no supplied VRoid
  reference render for a pixel-matched lighting comparison.
- No other combat clips, transformations, beam poses, mobile performance or
  physical-device behavior were tested. This scene uses studio lighting,
  not the battle arenas. Hair physics are retained through the importer but
  were not separately tuned or stress-tested.

Stop here. Keep the existing playable Kaizen until the new character's motion,
clothing deformation and combat contact have been reviewed in a later authorized
milestone. No roster redesign or game-wide work is included.
