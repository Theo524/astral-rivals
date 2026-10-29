# Skinned character and audio pipeline

The current fighters are imported, original skinned GLB assets. The old runtime
assembly of spheres/cylinders and procedural limb pivots has been removed from
`scripts/visuals/warrior_visual.gd`. That wrapper loads a `Skeleton3D`, weighted
`Skin` and `AnimationPlayer`; it does not generate a replacement primitive body
when an asset is missing.

The meshes, facial surfaces, hair locks, clothes, skeletons and animation poses
were authored with the included Blender Python tools. They are an improved
stylized work in progress, not a professional sculpt/retopology or finished
facial-animation set. No extracted commercial anime assets are included.

## Assets and reproducible sources

| Fighter | Runtime asset | Vertices | Triangles |
| --- | --- | --- | --- |
| Kaizen | `assets/characters/kaizen.glb` | 5,047 | 9,345 |
| Ryuzen | `assets/characters/ryuzen.glb` | 5,259 | 9,599 |
| Akira | `assets/characters/akira.glb` | 5,157 | 9,466 |

Each GLB contains one skinned mesh with 12 material surfaces, 18 skin joints and
25 animation clips. Its matching `<id>_asset.json` records the export counts and
clip metadata. The editable sources are `tools/blender/source/<id>.blend`.
That source folder has `.gdignore`: Godot imports the delivered GLBs rather than
attempting a runtime Blender conversion, including in the Android editor.

Regenerate from the project root with Blender 4.3 or newer:

```sh
blender --background --python tools/blender/build_characters.py
# Rebuild only one identity:
blender --background --python tools/blender/build_characters.py -- kaizen
# Skip costly offline review renders while rebuilding all assets:
ASTRAL_SKIP_REVIEWS=1 blender --background --python tools/blender/build_characters.py
```

`build_characters.py` creates custom smooth mesh surfaces and weights, then calls
`animation_library.py` to author bone keys. Quaternion normalization prevents
equivalent q/-q keys from causing interpolation discontinuities. Import the
updated GLBs in Godot before running the regression suites.

## Rig, facing and animation contract

The asset authoring coordinate system is Blender Z-up, facing -Y. glTF export
converts that face direction to +Z; the runtime wrapper rotates the model by PI
around Y so gameplay remains **-Z forward, +Y up**, with feet at ground level.
Do not apply that correction twice when replacing a model. The shared skeleton
includes root, hips, spine, chest, neck, head, paired arm/forearm/hand and paired
thigh/shin/foot bones. Characters stand approximately 2.2 metres tall.

Clips are `idle`, `walk`, `run`, `hover`, `fly`, `dash_forward`, `dash_back`,
`punch_1`, `punch_2`, `punch_3`, `kick`, `heavy`, `blast`, `beam`, `charge`,
`guard`, `parry`, `dodge`, `hurt`, `knockback`, `recovery`, `transform`,
`ultimate`, `victory` and `defeat`. They are baked at 30 FPS. The wrapper restores
loop flags for looping clips because glTF has no standard loop-mode field.

The existing visual interface is:

```gdscript
func setup(data: Dictionary) -> void
func anim_context(step: int, world_velocity: Vector3, facing: Vector3) -> void
func animate(delta: float, state: String, speed: float,
             attack_progress: float, form: int, airborne: bool) -> void
func set_form(form: int) -> void
func set_quality(level: int) -> void
func set_presentation(pose: String) -> void
```

`AnimationPlayer` uses manual processing. Gameplay maps attack progress onto
clip time so visual contact follows the simulation, with short crossfades
between clips. Light punches contact near 41% of their 0.34-second action; the
fourth roundhouse contacts at 0.205 seconds in its 0.5-second action. A heavy
contacts near 44% of its 0.64-second action. Recheck training and actual hit
windows after editing a clip; visual overlap does not determine damage.

The fighter's arena physics and deterministic horizontal rival separation stay
in `fighter.gd`. Decorative meshes never create combat colliders. Preserve the
visual API when substituting a manually sculpted/rigged model; do not rewrite
the shared combat logic just to replace art.

## Materials and quality settings

Imported colours/textures are converted by the wrapper to
`shaders/anime_toon.gdshader` and `anime_outline.gdshader`. The outline is an
extra inverted-hull pass. Hair materials are identified by name for form colour
changes. `energy_aura.gdshader` renders a bounded instanced aura; it is separate
from the body mesh. Preserve meaningful material names, normals and culling
when importing replacement art.

Current GLB imports generate mesh LOD data. Quality changes the mesh LOD bias
and visible aura count while retaining the same skinned silhouette and face.
No phone polygon/draw-call budget has been certified. Profile outlines,
transparent effects, bones and texture memory on actual devices before a
release; importing a higher-resolution sculpt alone is not an optimization.

Godot gameplay screenshots live in `docs/review/godot_*.png`. Separate Blender
CPU studio/pose reviews in the same folder show asset geometry, not the exact
Godot shader or gameplay camera. `tools/blender/render_review.py` re-renders
those existing Blender sources without rebuilding the runtime GLBs.

## Audio and external assets

`scripts/effects/audio_manager.gd` generates original 22,050 Hz WAV cues and a
short looping music pattern, with 12 pooled playback voices. These are
functional placeholders, not a mastered soundtrack. Replace entries in its
`sounds` dictionary with imported original/licensed WAV/OGG streams while
preserving `play(cue)`, volume and app-suspension behavior.

Existing cue keys include hit, heavy, blast, beam, charge, dash, dodge,
transform, explosion, menu, guard, parry, win and lose. Keep author, source,
license/attribution and modifications for any external asset added later. Do
not substitute copyrighted game models or soundtrack samples.
