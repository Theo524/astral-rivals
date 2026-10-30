# Phase 1F — private recovery checkpoint

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

## Not yet verified at this checkpoint

The edited body and new punch have not yet been reviewed together in rendered
front/side motion. Skin weights are unchanged; sleeve deformation is unresolved.
Native Godot reimport, expression checks, neutral before/after renders, contact
verification and animation previews still need completion. No replacement has
been installed in the playable game. No Windows or Android build was made.

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
