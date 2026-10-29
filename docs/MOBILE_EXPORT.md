# Mobile export and device validation

Astral Rivals is a source project built and checked with Godot **4.6.3**. The
checked-in export presets produced a standalone Windows x64 game and an
Android arm64 development APK. Matching templates and real open-source signing,
alignment and JDK tools were obtained for this build. The APK's v2/v3 signatures
and packaging were checked. No physical phone execution, iOS IPA, mobile FPS
measurement, production signing identity or store approval is claimed.

## Run the source

1. Install Godot 4.6.3 Standard, not the .NET edition requirement; this project
   uses GDScript and needs no .NET runtime.
2. Import `project.godot` in Godot's project manager. Allow the first resource
   import to complete, then press **F6** on `scenes/main.tscn` or **F5** to run.
3. Select a mode, character, opponent, arena, and difficulty from the menu.
   Training is the easiest place to verify inputs.

The project uses a 1280×720 logical landscape canvas. Touch controls scale with
the viewport. `display/window/handheld/orientation=0` requests landscape. Confirm
that the orientation, safe areas, text sizes, and controls behave correctly on
the actual display ratios you support.

On a Linux system with a graphical display:

```sh
godot --editor --path /path/to/astral-rivals
godot --path /path/to/astral-rivals
```

In a restricted environment where Godot cannot write its default user-data
directory, set writable XDG directories for each command:

```sh
XDG_DATA_HOME=/tmp/godot-data XDG_CONFIG_HOME=/tmp/godot-config \
XDG_CACHE_HOME=/tmp/godot-cache godot --headless \
  --path /path/to/astral-rivals --editor --import --quit
```

A headless run validates simulation and script behavior; it does not establish
visual quality, GPU performance, real audio output, or physical multitouch.

## Android arm64

1. In Godot, install the **4.6.3 export templates** using Editor → Manage Export
   Templates. The template version must match the editor.
2. Install the Android SDK and the JDK version supported by Godot 4.6.3 (Godot's
   Android export setup recommends OpenJDK 17). Install the platform tools and
   the SDK/build-tools versions required by that Godot release. Set **Java SDK
   Path** and **Android SDK Path** in Editor Settings → Export → Android.
3. Open Project → Export → Android. The preset enables **arm64-v8a** only,
   uses APK output without a Gradle build and takes the template's SDK values
   (the produced manifest has minimum API 24 and target API 36). Leave the
   Min/Target SDK overrides blank in this mode: Godot rejects those overrides
   unless Gradle is enabled. Verify distribution requirements before shipping.
4. Create `build/android/`. Use **Export With Debug** for device testing; Godot
   can use its configured debug keystore. To distribute a release, configure
   your own package identity and release keystore through Godot's export UI.
   Keep keystores, passwords, and export credentials outside source control.
5. Enable USB debugging on a device, install the debug APK, and review logcat
   while testing. No network or microphone permission is requested by the
   starter preset.

After SDK and templates are configured:

```sh
mkdir -p build/android
godot --headless --path . --export-debug Android build/android/astral-rivals.apk
adb install -r build/android/astral-rivals.apk
```

For a Play Store bundle, enable the Android Gradle build, install the matching
Android build template in the project, choose AAB output, and configure release
signing. Those distribution steps have not been performed here.

## iOS

Use a macOS machine with Xcode, the iOS SDK, an Apple development team, suitable
provisioning profiles, and the matching Godot 4.6.3 export templates. Open the
**iOS** preset and replace the example bundle identifier with your app's identity.
Enter your team and signing configuration locally. The preset requests an
**Xcode project only**, keeping signing and device/archive builds in Xcode.

Create `build/ios/`, export the Xcode project, open it in Xcode, select the team
and a physical iPhone/iPad, then build and run. Check supported orientations in
the generated target settings and verify landscape safe areas on device.

The project selects **GL Compatibility** for desktop/Android and an explicit
**Mobile renderer override for iOS**. Test every material/effect on the selected
iOS backend (Metal or MoltenVK, depending on export configuration). iOS
compilation, shader behavior, touch input, signing, and performance remain
unverified here.

## Linux desktop package

Install the matching Linux export templates and then:

```sh
mkdir -p build/linux
godot --headless --path . --export-debug 'Linux Desktop' \
  build/linux/astral-rivals.x86_64
```

The source can run directly in the editor even when export templates are absent.

## Performance settings and release checks

The settings UI offers Low/Medium/High quality, a 30/60 FPS cap, camera shake,
master volume, touch-button scale, and joystick sensitivity. Saved values live
in `user://settings.cfg`. A frame cap is a target, not a guaranteed measured rate.
There is no automatic thermal-adaptive frame-rate controller.

Arena quality `0` disables directional shadows, dust/smoke banks, and reduces
scatter/debris. Higher arena quality enables one directional shadow map with a
70-unit maximum distance. Static architecture, repeated scatter, clouds, and
windows use MultiMesh batches. Projectile/effect counts are bounded by their
system, and its `quality` setting reduces optional effect density. Check the
actual build's settings application when adding more renderer options; the
quality labels alone do not guarantee a given resolution, polygon budget, or
frame rate.

Before a mobile release, record results from physical devices:

- Low/mid/high GPU tiers: sustained combat, beams, transformations, smoke,
  impact destruction, frame times, memory, temperature, and battery draw.
- Simultaneous joystick movement, attacks, guard/charge, ascent/descent, and
  touch release/cancellation while another finger remains down.
- Wide/notched screens, safe areas, readable HUD, button scaling, and portrait
  rotation attempts; Android back/pause and app background/resume behavior.
- Audio latency, volume, headphones, interruptions, gamepads, and save/settings
  persistence after process restart.
- At least one complete match and mode progression through victory and defeat,
  all characters/forms, all arenas, and extended survival sessions.

Use Godot's monitors and remote profiler, Android GPU Inspector/Perfetto or
Xcode Instruments as appropriate. Tune render scale, shadows, particles and
outline passes from measurements. The present project is a playable prototype,
not a certified 60 FPS mobile release.
