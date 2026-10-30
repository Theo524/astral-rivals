# Phase 1E — private pose corrections only

Starting point: `0d6c833`. This milestone changes generic animation tools and
the private inspection scene only. The user's VRM, converted native character,
face, hair, textures and expression library are retained. No character modeling,
new joints, game/combat changes or Windows/Android builds are included.

## Changes

- `martial_pose.gd` adds a pose layer after legacy motion transfer. It measures
  the existing arm chains, solves elbow/wrist targets, resets inherited shoulder
  roll and sets hand orientation from palm/finger landmarks.
- Idle now has separated closed/relaxed fists near the cheeks, lower elbows and
  a restrained torso/chin angle. It no longer uses crossed open palms.
- Walking keeps the existing leg motion, with a smaller pendulum arm swing,
  slight elbow bend and inward-facing palms below the torso. The previously
  twisted arm positions are removed in the inspected frames.
- `finger_pose.gd` uses the existing finger/thumb joints. Curl axes come from
  hand anatomy rather than assumed mirrored Euler axes. Relaxed walking hands,
  guard fists and attack fists have separate amounts; poses are written from
  rest each update to avoid accumulating rotation.
- The one left punch has a windup, torso turn, slight clavicle protraction,
  forward extension and recovery. Peak wrist reach targets 95% of its measured
  arm chain; the opposite hand stays in guard. Strike height is slightly below
  the shoulder to reduce garment stress.
- The private viewer labels clip, phase and actual source-animation time.
  Windup, contact and recovery labels are distinct.

These are runtime pose corrections for **idle, walk and punch_1 only**, not a
completed animation library or an enabled replacement for the playable fighter.

## What the contact frame proves

A separate red practice pad is calibrated to this avatar's corrected reach,
then remains fixed throughout windup, contact and recovery. A 2.5 cm spherical
probe at the punching knuckles is checked against its real physics collider:

1. At the initial guard, there is no overlap.
2. At normalized phase **0.41**, the knuckle probe overlaps the pad.
3. After recovery, there is no overlap again.

The contact screenshot is taken at that verified pose, with the frame's actual
AnimationPlayer time printed in the image. The final contact time is about
0.150 seconds for the currently imported source clip; it is not assumed from a
nominal game-action duration.

This is an **explicitly staged inspection fixture**, not a live fight, opponent
hit or damage-system test. The probe approximates hand volume; it does not
certify exact skin-surface collision or modify the game's hitboxes.

## Verification

- The actual private humanoid resolves the required arm, hand and finger bones.
- Each of the three allowed clips is sampled at seven phases. All corrected
  bone transforms remain finite.
- Guard hand height, walking hand height, visible lead-fist travel, arm reach
  beyond 88% of chain length and actual finger bending are checked.
- Fixed-pad no-contact/contact/recovery tests pass.
- Blink still drives the existing facial morphs, then restores the neutral
  expression. The source VRM and native `.scn` match their Phase 1D copies
  byte-for-byte; no private asset was re-exported or remodeled.
- Actual Godot OpenGL captures inspect guard, walking, punch windup, contact and
  a guard close-up. Rendering uses Xorg / Mesa llvmpipe on Linux; it is not a
  mobile performance or hardware test.
- Existing game regression suite: **314/314 passed**. The public retarget
  mathematics regression also passes for its nine source/synthetic-rig samples.

Private images are saved in the experiment's `results/` directory:

| File | Exact pose shown |
| --- | --- |
| `idle_guard.png` | Idle guard, phase 0.15 |
| `guard_close_up.png` | Same guard, close-up |
| `walking.png` | Walking, phase 0.25 |
| `punch_windup.png` | Punch windup, phase 0.20 |
| `punch_contact.png` | Punch at verified fixed-pad contact, phase 0.41 |

These images, private reports, source/derived models and textures are **not**
included in the public GitHub commit. Only generic scripts, script identifiers
and documentation are published. Other fighters, public game assets, combat
code, modes and exports remain unchanged.

## Running the private experiment

Use the [Phase 1D setup instructions](KAIZEN_PHASE1D.md) with the latest scripts
and a new output directory outside the public checkout. The preparer now copies
the arm/body and finger modules as well as the importer, retargeter and viewer.
For an existing private project, copy those five `.gd` files into its
`experiment/` directory, leaving `user_assets/` unchanged.

After the initial Godot editor import and private VRM conversion:

```sh
# Runs the three-clip pose/expression checks and fixed-pad contact checks.
godot --headless --path /your/private/experiment

# Renders the labelled inspection frames; requires a real graphical display.
godot --path /your/private/experiment --audio-driver Dummy \
  --fixed-fps 60 -- --capture
```

Without `--capture`, keys 1/2/3 select guard/walk/punch, Tab changes camera and
Esc exits. No playable game controls or scenes are changed.

## Remaining defects and stop

The extended punch still exposes **visible shoulder/sleeve clipping**. Walking
and guard are cleaner, but there is no claim that shirt deformation is solved.
Further improvement may require skin-weight/garment work, which was deliberately
excluded from this animation-only milestone.

Foot planting and full weight transfer remain based on the existing source
motion. Clip-transition blending, collision-free finger skin contact, motion
at other attack speeds, live combat timing and the rest of the roster/animation
library are not production-verified here. Keep the playable fighter unchanged.
Stop after these three poses and this single punch-contact inspection.
