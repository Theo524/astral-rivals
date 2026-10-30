# Astral Rivals

## Downloads

- **[Download Android APK](https://github.com/Theo524/astral-rivals/raw/refs/heads/main/downloads/AstralRivals-Android-0.2.0.apk)** — 64-bit Android 7 or newer. Open the file to install this development-signed testing build.
- **[Download Windows PC game](https://github.com/Theo524/astral-rivals/raw/refs/heads/main/downloads/AstralRivals-Windows-0.2.0.zip)** — extract the ZIP and double-click `AstralRivals.exe`. No Godot installation is needed.
- [Download folder and checksums](https://github.com/Theo524/astral-rivals/tree/main/downloads)
- [Release notes](https://github.com/Theo524/astral-rivals/releases/tag/v0.2.0)

The APK and Windows ZIP are stored directly in the repository because the connected app could not upload release attachments.

The game builds do not require the Godot editor. Android device execution and physical Windows hardware compatibility remain unverified; see the testing notes below.

**Latest source: Kaizen Phase 1 visual pass.** His model, face, hair, gi, hands,
boots and toon presentation have been refined while preserving the existing
combat and skeleton. See [rendered before/after review](docs/KAIZEN_PHASE1.md).
The downloadable **0.2.0 APK/Windows ZIP predate this source-only update**.

[Phase 1B replacement feasibility](docs/KAIZEN_PHASE1B.md) records the actual
Blender-source audit, licensed asset research and one isolated base-mesh import.
It identifies the modeled/rigged asset still needed; the playable art is unchanged.

[Phase 1D private VRM experiment](docs/KAIZEN_PHASE1D.md) adds reproducible
VRM 1.0 import and three-clip retargeting tools. The user's model and rendered
captures remain private; the playable game continues using the existing assets.

Astral Rivals is a playable Godot 4.6.3 anime arena fighter with three original
skinned warriors, authored skeletal animations, flight, melee and energy combat,
and four single-player modes. A standalone **Windows executable has been
exported**; ordinary players do not need the Godot editor to run that build.

This upgrade preserves the working combat systems. It replaces the runtime
primitive-body characters with imported GLB meshes and bone animation, adds fair
fight openings, fixes a reproduced fighter-overlap physics loop, and improves
camera framing, lighting, touch layouts and effects allocation. The artwork is
improved work in progress, **not finished professional/AAA anime character art**.

## Play the Windows build

1. Download the Windows game archive and choose **Extract All**.
2. Open its extracted folder and double-click **AstralRivals.exe**. Keep any
   files delivered alongside it in that folder.
3. Choose **Training** for a safe first fight, then **Enter the Arena**.
4. Let the countdown finish. The training dummy stays passive unless you enable
   **Training Dummy Attacks** in Settings.

The Windows export contains the game data; a separate `.pck` is not needed.
This workspace verified its executable format and game content, but has not
tested it on a physical Windows PC. The source ZIP is for development and is a
separate deliverable from the playable Windows archive.

A signed **Android arm64 testing APK** is also provided. Copy it to a 64-bit
Android 7 or newer phone, open it from Files and install it. It runs without the
Godot Android editor. It uses a development signing key and has passed packaging
and signature checks; actual phone execution and performance remain unverified.
See [player instructions](docs/PLAYER_GUIDE.md) for installation and crash-log guidance.

## First-fight controls

| Action | Keyboard | Xbox-style gamepad |
| --- | --- | --- |
| Move / camera | WASD or arrows / hold right mouse and drag | Left / right stick |
| Light combo / heavy launcher | J / K | X / Y |
| Blast / beam | L / E | B / left stick click |
| Hold guard / vanish dodge | Q / X | LB / A |
| Directional dash | Shift + movement | RB + movement |
| Rise / descend | Space / Ctrl | RT / LT |
| Hold charge / transform | C / T | D-pad down / D-pad up |
| Lock toggle / pause | Tab / Esc or P | Right stick click / Start |
| Sphere / homing blast / nova / ultimate | V / H / O / R | Charge + blast / guard + blast / charge + heavy / beam in ultimate form |

Hold **C / Charge** to recover energy. Transform twice to unlock the final form;
transformations cost 30 then 55 energy, and an ultimate requires 85 energy.
Press J repeatedly to buffer a punch chain and its fourth-hit roundhouse.
Heavy attacks launch opponents; use rise or a pursuit dash to follow them.
Timed guards can parry, and a well-timed vanish opens a counter window.

Touch buttons appear by default on mobile. On PC, Settings can show them for
mouse testing. Touch supports simultaneous movement and held actions, three
layout presets, button sizing and sensitivity. Settings also offer fullscreen,
window resolution, graphics quality, 30/60 FPS caps, camera shake and volume.
**F11** or **Alt+Enter** toggles fullscreen on desktop.
Fresh mobile installs default to Low/30 FPS to keep startup conservative; choose
Medium/High or 60 FPS in Settings after checking your phone. The skinned models
and their facial geometry are retained at every preset.

## What is included

- Kaizen, Ryuzen and Akira, each with a distinct appearance, stance, stats,
  energy strength and three forms. Each imported mesh has a real weighted
  18-bone rig and 25 authored clips; no primitive body fallback is used.
- Ground and aerial movement, pursuit dashes, four-hit chains, launchers,
  knockback, guard breaks, parries, counters, evasions and actual hit timing.
- Swept blasts, spheres and homing attacks, interruptible beams, beam clashes,
  nova and ultimate attacks with energy costs and cooldowns.
- Three arenas with collision, batched scenery, limited breakable props and
  temporary impact scars; pooled impacts, sparks, auras, trails and screen lines.
- Passive-by-default Training, Versus AI, three-round Arcade and escalating
  Survival. Every round has a protected three-second countdown. AI gives a
  movement grace period, pursues melee first, spaces ranged attacks and cannot
  open with a beam in its first 6–8 active seconds, depending on difficulty.
- Live 3D character selection, HUD, pause/results, tutorial, saved preferences
  and career records. Original synthesized effects and a short music loop.

## Verification and remaining limits

`./tools/check.sh` passed **314 assertions**: combat 84, energy/camera/effects 27,
UI/input 71, match lifecycle 81 and imported animation 51. A separate actual
OpenGL run on Linux software rendering captured menu, arena, melee, beam,
transformation, pause and character selection. See [test evidence and render
scope](docs/TEST_RESULTS.md) and [Godot captures](docs/review).

Software rendering establishes visible output, not phone performance. Physical
gamepad/touchscreen use, Windows-device behavior, Android stability, thermal
limits and frame pacing still need hardware testing. **60 FPS is a target, not
a measured mobile result.** No Android crash cause can be established without
the reported device's logs. Bounded session evidence is written to
`user://logs/session.log`, with the prior run retained separately.

Character hands, hair locks, clothing sculpt detail and facial animation still
need an artist's production pass. The clips are authored keyframes, not motion
capture; no facial blend-shape acting or cloth simulation is implemented. Audio
is functional synthesized placeholder sound design. Destruction is limited
props/scars, not terrain deformation, and online multiplayer is absent.

## Open or rebuild the source

Use Godot **4.6.3 Standard**; no .NET runtime or commercial plugin is required.
Import `project.godot`, allow its GLB imports to finish, then press **F5**.

```sh
./tools/run.sh
./tools/run.sh -- --training
./tools/check.sh
./tools/build_windows.sh
./tools/build_android.sh
```

Native rebuilding needs the matching export templates and platform tooling.
See [mobile/export instructions](docs/MOBILE_EXPORT.md) and the [actual asset
pipeline](docs/ASSET_PIPELINE.md). Source characters and animation authoring
scripts are included; runtime assets do not require Blender.
