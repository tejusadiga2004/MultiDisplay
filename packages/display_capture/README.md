# display_capture

Native platform implementation for the Display Controller app's
`display_capture_api`. It enumerates displays, manages screen-capture sessions,
publishes frames as Flutter textures, reports capture/display events, and applies
native display-window chrome.

## Platform support

- **Windows:** Rust capture/rendering core with a C++ Flutter plugin.
- **macOS 14+:** Swift package using ScreenCaptureKit for capture and Metal with
  IOSurface-backed buffers for rendering.
- **Linux:** Not implemented.

The macOS implementation is built with Flutter's Swift Package Manager
integration. Enable it with the Flutter SDK commit pinned in the repository's
root [README](../../README.md), then build or run the app from the repository
root. macOS Screen Recording access must be granted in System Settings; restart
the app after granting access.

This is an application-specific plugin and is not published to pub.dev.
