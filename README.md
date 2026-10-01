# Display Controller

Lists every display connected to the machine (including virtual ones) and mirrors
each display you switch on into its own always-on-top window. See [SPEC.md](SPEC.md)
for the full specification. Only the Windows platform layer is implemented so far.

## Requirements

- Windows 10 2004 (build 19041) or newer
- Visual Studio 2022 with the "Desktop development with C++" workload
- Rust (stable, MSVC toolchain)
- **Flutter `main` at commit `fab991537bf1ffb063579a0dd8a47cd4f2874618`**
  (3.49.0-1.0.pre-200). The app uses Flutter's experimental windowing API, which
  Flutter changes without notice, so use exactly this commit:

  ```bash
  git clone https://github.com/flutter/flutter.git C:\flutter
  git -C C:\flutter checkout fab991537bf1ffb063579a0dd8a47cd4f2874618
  flutter config --enable-windows-desktop --enable-windowing
  ```

## Build and run

```bash
flutter pub get
flutter run -d windows
flutter build windows --release
```

The build also compiles the Rust platform layer
(`packages/display_capture/native`) through the plugin's CMake.

## Continuous integration

[`.github/workflows/windows-build.yml`](.github/workflows/windows-build.yml) runs on
every push to `main`/`master`, every pull request and on demand. It installs Flutter
at the pinned commit, runs `flutter analyze`, the Dart and Rust tests, builds the
release app and uploads `display-controller-windows-x64.zip` as a workflow artifact.

To move to a newer Flutter, change `FLUTTER_COMMIT` in the workflow and the commit
above together, after checking that the app still builds and runs.

## App icon

`windows/runner/resources/app_icon.ico` and `assets/icon/app_icon.png` are generated
by `tools/make_icon.ps1`.

## Debug switch

`DC_DEBUG_NO_CAPTURE_EXCLUSION=1` stops DisplayWindows from hiding themselves from
screen capture, so they show up in screenshots. Use only for testing, and never place
a window on the display it mirrors while it is set.
