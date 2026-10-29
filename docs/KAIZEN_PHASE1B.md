# Kaizen Phase 1B — replacement feasibility

Research and one isolated asset-intake experiment, 2026-10-29. Baseline:
`fb87fb23d52d235858416d98eb1a3c93d49ed206`. **No playable model replacement
was made.** No ready anime fighter was verified as both suitable and legally
available for raw redistribution in this public repository. The current Kaizen
art remains prototype quality.

## Decision

The strongest verified open foundation is Blender Studio's **Human Base Meshes
v1.4.1**, specifically its non-primitive **Body Male - Stylized** topology.
It is a starting point for an artist, not a sculpted/rigged Kaizen. The realistic
body in the same bundle is another anatomical reference; neither supplies the
required anime face, hair, martial-arts clothing or working fighter rig.

Use that foundation for a manually designed original character, or commission
the complete original asset. Do not continue adding rings, patches or detail to
the existing body. Do not treat buying a generic anime base as evidence of a
finished fighter without inspecting its anatomy, rig and redistribution rights.

## What inspection found in the existing Blender source

The actual `tools/blender/source/kaizen.blend` contains:

| Observation | Result |
| --- | --- |
| Source vertices / triangles | 7,819 / 13,957 |
| Connected mesh islands / boundary edges | 161 / 1,233 |
| UV layers / image textures / shape keys | 0 / 0 / 0 |
| Vertices with one bone influence | 7,231, approximately 92.5% |
| Vertices with two influences | 588 |
| Skeleton / animation Actions | 18 bones / 25 clips |
| Finger, eye or jaw bones | None |
| Unweighted vertices | 0 |

Separate hair, clothing and facial islands are normal in production assets, so
island counts alone are not a quality score. Here the counts, inspection of the
loft/patch authoring code and the previous actual renders show the underlying
problem: assembled anatomical sections, rigid hands, limited joint deformation
and flat facial surfaces. The rig functions, but a shader cannot supply missing
anatomy, facial topology or deformation design.

[Machine-readable source audit](review/phase1b_kaizen/current_source_audit.json).

## Asset routes investigated

| Route and primary source | What is established | What remains unavailable or unsuitable |
| --- | --- | --- |
| [Blender Studio Human Base Meshes](https://www.blender.org/download/demo-files/) | Official listing identifies v1.4.1 as CC0. Downloaded the actual bundle; the selected collection identifies Julien Kaspar as author and CC0 as its license. | A continuous, UV-mapped anatomical base; no deformation rig, skin weights, clips, hair or outfit. Its generic stylized face still needs a deliberate anime sculpt. Best verified open foundation, not a finished replacement. |
| [LessaB3D Anime Male — Base Mesh](https://thiagolessa.artstation.com/store/p0p0G/anime-male-base-mesh) | Creator advertises a Blender 3.5 file, textures and an Auto Rig Pro rig usable without the plugin. Listed standard license is $10, one commercial project with sales/view limits. | Purchase required; file, topology and deformation quality were not inspected. Permission to publish editable mesh/textures on GitHub was not established. No purchase or redistribution attempted. |
| [Original model authored in VRoid Studio](https://vroid.com/en/studio/guidelines) | Official guidelines permit broad use/editing of models made with unrestricted supplied content. Presets are not CC0; special asset/model conditions still apply. | No Kaizen `.vroid`/VRM was available here. Requires actual authoring and additional work for muscular anatomy and layered gi. Downloaded Hub avatars cannot be assumed to share those rights. |
| [MakeHuman / MPFB core anatomy](https://download.makehumancommunity.org/about/license.html) | Official project distinguishes CC0 core graphical assets from the program's software license. | Alternative anatomical foundation, not an anime head/hair/outfit solution. Third-party community assets have separate licenses. No second generator/install experiment undertaken. |

Evidence was checked on the date above; listing prices and terms may change.
Commercial game embedding and publishing editable source are different rights.
No marketplace model or copyrighted-franchise character was downloaded.

## The one implementation experiment

Downloaded **50,643,039 bytes** from Blender's official public server:

<https://download.blender.org/demo/asset-bundles/human-base-meshes/human-base-meshes-bundle-v1.4.1.zip>

SHA-256:
`811f43accbb31a88266d932f8f5563b2d13586fca0ba2693aad1f5fe582b3515`.
ZIP CRC verification passed. The bundle and temporary GLB remain outside the
project; no third-party mesh was committed to the game.

The read-only Blender inspection tool opened the bundle with scripts disabled.
It examined `GEO-body_male_stylized` and its two separate eye meshes, rather
than any of the bundle's primitive blocking assets. The body has **12,502
vertices, 12,500 quads / 25,000 triangles, one connected component, zero
boundary edges and a UV map**. The full bundle has **zero armatures and zero
animation Actions**; the selected body and eyes have no vertex weights.
The bundle's supplied topology previews were visually inspected; these were
creator previews, not new Godot screenshots or proof of finished anime art.

An isolated export of those three authored meshes was then imported with
Godot's actual `GLTFDocument`, without replacing any game asset:

```text
Godot 4.6.3: GLB import OK
MeshInstance3D: 3
Skeleton3D: 0
Skinned meshes: 0
AnimationPlayer: 0
meets_current_warrior_rig_preconditions: false
```

This proves file-format intake only. It does **not** verify combat integration,
skinning/deformation, appearance in-game or a successful Kaizen replacement.
Renaming the file to `kaizen.glb` would remove the existing usable rig/clips;
the runtime visual loader requires a skeleton and animation player. Automatic
weights, procedural replacements and repeated art variations were not attempted.

The full bundle emits warnings about example mask drivers with scripts
disabled. Its legacy `License` text block names the **Rain Rig** under CC-BY
4.0, while the selected **Body Male - Stylized** collection metadata and
official bundle listing say CC0. Those are recorded separately; the text block
is not treated as a blanket license for every asset. The exporter also reports
its unavailable optional Draco library; the GLB uses no Draco compression and
imports successfully. No claim of a warning-free Blender session is made.

Reports: [candidate audit](review/phase1b_kaizen/blender_stylized_male_audit.json),
[Godot intake](review/phase1b_kaizen/godot_intake.json).

### Reproduce the isolated intake

Download/unzip the official bundle outside the project, then run:

```sh
blender --background --disable-autoexec \
  --python tools/blender/inspect_character_source.py -- \
  /tmp/human_base_meshes_bundle.blend /tmp/base-audit.json \
  --mesh GEO-body_male_stylized \
  --mesh GEO-body_male_stylized.eye.L --mesh GEO-body_male_stylized.eye.R

blender --background --disable-autoexec \
  --python tools/blender/export_base_intake.py -- \
  /tmp/human_base_meshes_bundle.blend /tmp/kaizen-base-intake.glb

godot --headless --path . --script res://tools/kaizen_base_intake.gd -- \
  /tmp/kaizen-base-intake.glb /tmp/godot-intake.json
```

The exporter refuses outputs inside the project. The Godot check expects this
specific unrigged candidate and exits successfully only when it imports as
three meshes without being mistaken for a working fighter. The inspection
tool can also audit `tools/blender/source/kaizen.blend` without changing it.

## Asset needed to finish replacement

Give an anime character artist the original Kaizen concept, existing renders,
this repository and the CC0 foundation link. Request:

1. An adult athletic shonen male sculpt: natural shoulders/chest/waist/legs,
   properly shaped palms and fingers, a sharp original anime face with useful
   eyelid/mouth loops, expressive brows and sculpted directional hair clumps.
2. Separate believable blue gi layers, folds, belt, gloves and boots. UVs and
   authored textures; hair materials kept distinct for golden transformations.
   Do not reuse the current ring-loft anatomy or franchise-derived assets.
3. A weighted deformation rig with finger control and facial expressions.
   Retain those extra bones/morphs; the game does not require exactly 18 bones.
   Deliver editable `.blend`, textures, a game-ready `.glb` and license records.
4. Retarget the existing 25 clips, correcting rest poses and bone axes rather
   than merely renaming bones. Preserve current action lengths/contact timing;
   inspect shoulders, elbows, wrists, hips and knees in idle/punch/kick/beam.
   Match the documented metre scale, grounded feet and gameplay facing.
5. Rights that explicitly cover modification, commercial PC/mobile game use
   **and public distribution of the editable assets** in this GitHub repository.
   Commissioning original work with those written rights avoids the unresolved
   marketplace-source restriction. No artist was contacted in this task.

Accept the model only after rendered head/hand/full-body review and deformation
inspection. Put its first integration in a separate candidate asset path;
replace the playable `kaizen.glb` after visual review and clip/gameplay checks.
This work requires an actual modeled/rigged asset, not another shader pass.

## Preserved game and stopping point

`./tools/check.sh` exited 0: **314/314 existing checks passed**. See
[recorded output](review/phase1b_kaizen/game_checks.txt). Intake import and
Python compilation also pass. The playable assets, shaders, game scripts,
Ryuzen/Akira, modes, combat mechanics and export configurations remain identical
to `fb87fb2`. No Windows/Android package was rebuilt.

No visual replacement was implemented, so there are no new Kaizen close-up or
full-body renders claimed by this milestone. Existing Phase 1 screenshots still
show the current game. Research and this single intake experiment stop here.
