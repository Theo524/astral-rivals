# Astral Rivals: player installation and controls

## What is available in this delivery

The updated Godot source project, a standalone **Windows `.exe`**, and an
installable **Android `.apk`** are available. Neither native application
requires the Godot editor. The Windows executable embeds its game content;
the APK includes its actual arm64 libraries and game assets. Do not treat a
`.pck` resource pack as a standalone game: it still requires a matching Godot
executable.

Windows and Android are configured release targets. Matching export templates
were obtained after the initial tooling limitation was resolved, and the
Windows preset produced a valid x86_64 executable. The Android APK's ZIP/ELF
packaging and v2/v3 debug signature were verified using the actual archive and
`apksigner`. Native Windows hardware and Android device testing remain separate
from export verification.

## Windows

1. Download the **Windows game ZIP**, then right-click it and select **Extract
   All**. Do not run the game from inside the ZIP preview.
2. Open the extracted folder and double-click **AstralRivals.exe**.
3. Keep any accompanying files beside the executable. The current Windows
   preset embeds game data into the executable; future builds may ship extra
   libraries or content beside it.
4. Start with **Training**, then choose a warrior and stage. Training uses a
   passive practice partner unless **Training Dummy Attacks** is enabled in
   settings.

An exported Windows game does not require the Godot editor. The supplied
executable is unsigned; no production publisher certificate was available.
Review the final test report for any Wine/Linux compatibility checks, which do
not replace testing on an actual Windows PC.

Use **Settings** to change fullscreen/windowed mode, window resolution,
graphics quality, frame cap, camera shake, and audio. Touch controls can be
shown on PC for mouse-based testing; they are hidden by default on desktop.

## Android

1. Transfer **AstralRivals.apk** to your phone and open it from your Downloads
   or Files app.
2. If Android asks, allow that Files/browser app to install this APK, then tap
   **Install**. Review the source and publisher before installing any APK.
3. Open **Astral Rivals** from your apps list and hold the phone sideways.
4. Begin in **Training**. Use **Settings** to select a touch layout, adjust
   button size/sensitivity, and choose Low/30 FPS if needed.

A standalone Android game does not require the Godot Android editor. Running
the source inside that editor is a separate workflow, with additional memory,
import and editor overhead. No physical-device validation was performed;
native Android crash behavior remains unverified. The provided APK is signed
with a **debug testing certificate**, not a production publisher identity.

The actual exported manifest requires **Android 7.0 / API 24 or later** and
targets API 36; the APK is **arm64-v8a only**. Its compressed native libraries
are marked for extraction by Android, and their ELF load segments have 16KiB
alignment. These are verified packaging facts, not proof of execution on every
supported device or page-size configuration.

## First fight

Each round begins with a short countdown. Attacks are locked until **FIGHT**.
Normal opponents begin with a movement/melee opening rather than an immediate
beam. Difficulty affects reaction delay and attack variety. To practice safely,
leave **Training Dummy Attacks** off.

| Action | Keyboard | Xbox-style controller |
| --- | --- | --- |
| Move / camera | WASD or arrows / hold right mouse and drag | Left / right stick |
| Light combo / heavy launcher | J / K | X / Y |
| Blast / beam | L / E | B / left stick click |
| Hold guard / vanish dodge | Q / X | LB / A |
| Directional dash | Shift + movement | RB + movement |
| Rise / fall | Space / Ctrl | RT / LT |
| Hold charge / transform | C / T | D-pad down / D-pad up |
| Lock enemy / pause | Tab / Esc or P | Right stick click / Start |
| Charged sphere / homing shot | V / H | Charge + blast / guard + blast |
| Area nova / ultimate | O / R | Charge + heavy / beam in ultimate form with enough energy |

On touchscreens, hold the left joystick to move and press the labelled action
buttons with other fingers. Hold **Charge** to recover energy. Combining
**Charge + Blast**, **Guard + Blast**, or **Charge + Heavy** activates the same
special moves shown in the table. Transform twice to reach the final form;
transformation and stronger attacks require energy.

## If the game closes on Android

There is no device crash log in this workspace, so an Android crash root cause
has **not** been established. Record the phone model, Android version, whether
you used the Android editor or an exported APK, the selected renderer, and the
last action before the crash. A developer can collect an `adb logcat` excerpt
showing the exception or native backtrace. Avoid sharing unrelated personal
log entries.

The source includes conservative graphics settings and a Compatibility renderer
for Android, but those choices do not prove device stability. Editor crashes,
driver crashes, memory pressure, and game-script failures need different fixes;
none should be assumed without the actual log.

## What a build maintainer still needs

These steps are for the person producing native downloads, not ordinary players.

**Windows:** install Godot **4.6.3 Standard** and its exactly matching export
templates. Open Project → Export → **Windows PC**, then export a release build.
The preset targets x86_64, embeds the game data, and does not sign the binary.
On a Linux build machine, `tools/build_windows.sh /path/to/output` invokes the
same export. Set `GODOT_BIN` if the executable is not named `godot`.

**Android:** install the matching Godot export templates, the Android SDK
platform-tools/build-tools required by that release, and a supported Java SDK.
Set the Java SDK and Android SDK paths in Godot's editor settings. Configure a
local debug keystore for testing, then export **Android** with debugging enabled.
`tools/build_android.sh /path/to/output` performs that debug export. Store
release keystores and passwords locally, outside the source repository. The
current APK preset targets arm64-v8a and uses the matching Godot template's
minimum/target SDK defaults. API overrides require a Gradle build, so this
non-Gradle preset leaves them unset. Review the produced manifest and current
distribution requirements before publishing.

The workspace initially lacked matching templates and Android tools. Scoped
network access later allowed the matching Godot Windows/Android templates to be
obtained and the Windows application to be exported. A local Android APK
toolchain can be assembled from actual Debian-distributed open-source
`adb`, `apksigner`, `zipalign` and OpenJDK packages using
`tools/download_android_tools.py`; this does not accept Google's SDK license or
provide a full Gradle/platform SDK. `tools/build_configure_android.py` configures
a local debug-signing export profile. APK export and signature verification
have now succeeded using those real tools; no Google SDK terms were accepted
and no fake SDK executables were substituted.

After export, verify the Windows executable on Windows and install the APK on
actual Android devices. Check every warrior/form, menus, full matches,
multitouch, safe areas, pause/background/resume, sustained performance, and
crash logs before calling either build a supported release.
