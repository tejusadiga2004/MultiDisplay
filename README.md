# Display Controller

Lists every display connected to the machine (including virtual ones) and mirrors
each display you switch on into its own always-on-top window. See [SPEC.md](SPEC.md)
for the full specification. The Windows and macOS platform layers are implemented;
Linux remains planned.

## Requirements

- Windows 10 2004 (build 19041) or newer
- Visual Studio 2022 with the "Desktop development with C++" workload
- Rust (stable, MSVC toolchain)
- macOS 14 or newer with Xcode (macOS development/builds)
- **Flutter `main` at commit `fab991537bf1ffb063579a0dd8a47cd4f2874618`**
  (3.49.0-1.0.pre-200). The app uses Flutter's experimental windowing API, which
  Flutter changes without notice, so use exactly this commit:

  ```bash
  git clone https://github.com/flutter/flutter.git C:\flutter
  git -C C:\flutter checkout fab991537bf1ffb063579a0dd8a47cd4f2874618
  flutter config --enable-windows-desktop --enable-windowing
  ```

For macOS, install the same pinned Flutter commit and enable its desktop windowing
support and Swift Package Manager integration:

```bash
git clone https://github.com/flutter/flutter.git ~/flutter
git -C ~/flutter checkout fab991537bf1ffb063579a0dd8a47cd4f2874618
export PATH="$HOME/flutter/bin:$PATH"
flutter config --enable-macos-desktop --enable-windowing --enable-swift-package-manager
```

## Build and run

Windows:

```bash
flutter pub get
flutter run -d windows
flutter build windows --release
```

The build also compiles the Rust platform layer
(`packages/display_capture/native`) through the plugin's CMake.

macOS:

```bash
flutter pub get
flutter run -d macos
flutter build macos --release
```

On first launch, grant Screen Recording access in System Settings and relaunch
Display Controller before starting a capture.

## Capture window modes

The Controller's **Capture windows** control switches between:

- **Separate windows** (default): one capture window per selected display,
  preserving the existing placement, sizing and close behavior.
- **Single layout**: one window containing the selected displays in their current
  desktop arrangement. Negative origins, vertical offsets, mixed macOS backing
  scales and gaps are preserved; the complete layout is fitted into the window
  without stretching the capture textures.

The mode is independent of the **List / Layout** selection view. Switching modes
retains selected displays and recreates the output windows. Mode choice lasts
for the current launch; enabled display IDs continue to be saved between launches.
Newly connected monitors appear unselected. In Single layout, selection changes,
monitor moves and disconnects update the existing composite window; deselecting
the last display closes it. Closing the composite window clears all selections.
Capture failures are shown within the affected tile with a Retry button and do
not close other captures. Both modes retain always-on-top and capture-exclusion
behavior.

## Continuous integration

[`.github/workflows/windows-build.yml`](.github/workflows/windows-build.yml) runs
only on manual dispatch. It installs Flutter
at the pinned commit, runs `flutter analyze`, the Dart and Rust tests, builds the
release app and packages a per-user Inno Setup installer and portable ZIP.
The packages include the app-local Visual C++ runtime DLLs from Visual Studio's
redistributable directory, so installation does not require an elevated runtime
installer.
The workflow also smoke-tests silent installation and uninstallation.

[`macos-build.yml`](.github/workflows/macos-build.yml) also runs only on manual dispatch
using a macOS 26 runner. It installs the pinned Flutter revision and Xcode Metal
toolchain, enables multi-window support and Swift Package Manager, runs analysis
and Dart tests, and builds a universal release app for Apple Silicon and Intel.
It verifies both executable architectures, the app icon and compiled Metal
shaders, then packages a drag-to-Applications DMG and a portable ZIP containing
`Multi Display.app`. Both workflows upload installers, ZIPs and SHA-256 checksum
files as artifacts retained for 14 days.

Download the packages from the run's **Artifacts** section in GitHub
Actions. These CI builds use local/ad-hoc signing, not Developer ID signing or
Apple notarization; distributing a trusted app outside the App Store requires
additional Apple Developer credentials and signing/notarization steps. No Apple
credentials are needed for this build workflow.

To start either pipeline, open **Actions** in GitHub, select **Build Windows** or
**Build macOS**, then click **Run workflow** and choose the branch. Neither
workflow runs automatically on pushes or pull requests.

To move to a newer Flutter, change `FLUTTER_COMMIT` in both workflows and the
commit above together, after checking that the app still builds and runs.

## Installers (development builds)

Versioned filenames use `pubspec.yaml`, including its build number, for example:

- Windows: `Multi-Display-1.0.0-build.1-windows-x64-setup.exe`
- macOS: `Multi-Display-1.0.0-build.1-macos-universal.dmg`

Windows Setup installs to `%LOCALAPPDATA%\Programs\Multi Display` without
administrator privileges, creates a Start Menu shortcut, offers an optional
desktop shortcut and registers an uninstaller. A stable installer ID lets newer
installers update the same installation. Close the app before upgrading.
Uninstalling leaves user settings intact. Unsigned builds may trigger SmartScreen.

On macOS, open the DMG and drag the app onto the Applications shortcut. Quit the
app before replacing an older copy. The included `INSTALL.txt` describes Screen
Recording permission and development-build security warnings. Installing does
not grant permission automatically. Remove the app from Applications to uninstall;
settings are not intentionally deleted.

To package an existing release build locally:

```powershell
# Windows: Visual Studio C++ tools and Inno Setup 6 must be installed.
pwsh -File tools/installers/windows/package.ps1
```

```bash
# macOS: requires a universal release build.
bash tools/installers/macos/package.sh
```

Outputs are written to `build/installers/windows` or `build/installers/macos`.
Verify downloads against the accompanying `SHA256SUMS.txt` file using
`Get-FileHash -Algorithm SHA256` (Windows) or `shasum -a 256 -c <file>` (macOS).
These installers do not provide automatic updates or publish GitHub Releases.
Developer ID signing/notarization and Windows Authenticode signing remain a
separate distribution phase; no signing credentials are used by these workflows.

## App icon

Windows, macOS, and in-app icon assets are generated by `tools/make_icon.ps1`.

## Debug switch

`DC_DEBUG_NO_CAPTURE_EXCLUSION=1` stops DisplayWindows from hiding themselves from
screen capture, so they show up in screenshots. Use only for testing, and never place
a window on the display it mirrors while it is set.
