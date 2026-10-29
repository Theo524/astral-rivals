# Verification of the upgraded project

Checks were executed on 2026-10-29 using
**Godot 4.6.3.stable.official.7d41c59c4** in the Linux workspace. The existing
project and working combat systems were upgraded in place. The results below
separate simulation, actual graphical output, native export and device testing.

## Automated simulation and input

Command:

```sh
./tools/check.sh
```

Observed output, exit **0**:

```text
COMBAT TESTS: 84/84 passed
ENERGY_TESTS: 27/27 checks passed
UI_TESTS: 71 checks, 0 failures
GAME TESTS: 81/81 passed
ANIMATION TESTS: 51/51 passed
All Godot regression suites passed.
```

**314 assertions passed.** The wrapper uses isolated temporary user-data
directories and fails on script errors, failed checks or leaked-instance
warnings. These run actual Godot scripts/physics, not pseudocode or mirrored
mock combat implementations.

| Suite | Important behaviors checked |
| --- | --- |
| Combat | Startup/active timing, buffered combos, short-range contact, timed fourth kick, physical lunges, parries, guard breaks, dodge windows, launcher/pursuit physics, energy gates, transformations, knockout, protected countdown, melee-first AI opening and stable rival overlap |
| Energy/camera/effects | Swept hits, sphere/nova/homing damage, opposing projectiles/beams, channel interruption, finite pool limits, audio generation/teardown, quality limits and camera framing geometry |
| UI/input | Real touch/drag events, independent four-finger ownership, cancellation/focus loss, touch ability combinations, menu/results/tutorial actions, live 3D preview lifecycle, settings persistence, layout presets and desktop touch visibility |
| Game | Character/arena selections, HUD, three-second countdown, mobile focus pause/resume, training aggression setting, real melee victory, AI defeat/full-health fight, rematch/menu cleanup, arcade/survival progression, settings and diagnostic log creation |
| Animation | All three imported GLBs, 18-bone skeletons, real skin weights/ArrayMesh bodies, all 25 clips, finite poses, weighted arm/leg movement, manual AnimationPlayer, global facing, breathing, forms and low-quality rig preservation |

A separate 3,600-frame headless quickstart smoke also exited cleanly. Accelerated
fixed-FPS simulation does not measure a rendered 60 FPS rate.

## Actual Godot graphical rendering

The graphical harness explicitly rejects the headless display driver:

```sh
DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 ./tools/run.sh \
  --audio-driver Dummy --rendering-method gl_compatibility \
  --rendering-driver opengl3 --fixed-fps 60 \
  --script res://tests/render_smoke.gd
```

It ran through Xorg on **Mesa llvmpipe (LLVM 19.1.7), OpenGL 4.5 Compatibility**,
capturing actual 1280×720 viewport images. The log ends `RENDER SMOKE: passed`.
Captured phases are menu/live character preview, arena, melee, beam,
transformation, pause and Akira selection. See `docs/review/godot_*.png`.

A full-health graphical AI-versus-AI fight then completed through the real
countdown, combat, transformations and defeat screen. It ended after
**29.6858 simulation seconds**, with player health 0 and opponent health 329.714.
`godot_full_match.png` and `godot_match_result.png` are actual viewport captures.
This verifies the rendered match lifecycle, not a physical Windows or phone run.

This review exposed over-bright toon illumination and excessive arena lighting;
the lighting calculation was normalized and lighting/camera framing adjusted,
then the graphical harness was rerun. The Xorg/software driver warns that it
cannot change V-Sync mode. No GPU/mobile FPS claim follows from this test.
Audio used the Dummy driver, so it does not verify actual speaker output.

Five additional Blender Cycles CPU renders inspect Ryuzen/Akira idle and Kaizen
punch, kick and beam poses. They show attached limbs and coherent weighted
poses, but are **asset renders**, not Godot gameplay. They also show remaining
art limits: simplified fists, broad garment forms and limited hair/cloth detail.
Rendered verification does not make these assets finished professional art.

## Native builds and platform scope

A matching Godot **Windows x86_64 release executable** has been exported to
`/workspace/releases/windows/AstralRivals.exe`, with embedded game data. Its
file type is PE32+ Windows GUI/x86-64, approximately 101 MB. It is a standalone
game export, not a `.pck` requiring the user to install an editor. Physical
Windows launch, graphics drivers and gamepad behavior remain untested here.

The real Windows PE executable also completed a 300-frame headless launch
under locally installed Wine 10, exit 0. It then rendered and recorded its
live 3D menu through Wine/OpenGL. These are Windows-binary compatibility tests
on Linux, not a test of a physical Windows installation. Movie-capture testing
exposed a Dummy-audio cleanup warning, so cleanup now recognizes the Dummy
driver for graphical captures as well as headless tests. Forced MovieMaker
shutdown still reports retained AudioStream objects at exit; this capture-only
warning is recorded rather than treated as a clean teardown. Ordinary
headless regression runs and the complete graphical match exit cleanly.

An isolated `--headless --write-movie` probe also exposed a Godot dummy-renderer
null-texture crash before loading the game. This unsupported capture path is
excluded from the graphical harness, which requires actual OpenGL. Neither
tooling result establishes a cause for the reported Android-editor crash.

The Android arm64 APK was exported and verified using real `apksigner`: v2 and
v3 signatures pass with the standard development certificate. ZIP CRC and
embedded assets passed inspection. The actual manifest has minimum SDK 24,
target SDK 36, landscape orientation and native-library extraction enabled.
Both compressed arm64 libraries have 16 KiB ELF load-segment alignment. These
are packaging checks; no device execution or mobile compatibility is claimed.
iOS remains a future export path, not a produced build.

The reported Android-editor crash has not been reproduced on a device and no
device log was provided. The actual overlap physics loop was reproduced and
fixed, but is not asserted to be the Android crash cause. Startup allocation was
reduced from 88 effect roots/264 meshes to 30 roots/106 meshes on Low. This is a
measured source allocation reduction, not a measured phone-memory/FPS result.

The game writes bounded event/monitor evidence to `user://logs/session.log` and
retains the previous session. App focus loss pauses combat/countdown, clears
touch pointers and suspends audio. These code paths are tested; operating-system
kill, renderer faults, thermals and native mobile lifecycle still require devices.
