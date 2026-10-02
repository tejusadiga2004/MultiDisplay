import 'models.dart';

/// Uniform, platform-independent API used by the UI layer (SPEC §6.1).
abstract class DisplayCaptureApi {
  /// Current displays ordered primary-first, then by originX, originY, id.
  Future<List<DisplayInfo>> listDisplays();

  /// Emits the full new list whenever displays are added/removed/changed.
  Stream<List<DisplayInfo>> get displaysChanged;

  /// Starts capturing [displayId]; returns the Flutter external texture.
  Future<CaptureSession> startCapture(String displayId,
      {CaptureOptions options = const CaptureOptions()});

  /// Stops and releases a session. Safe to call twice.
  Future<void> stopCapture(int sessionId);

  /// Hides the controller and capture windows, then stops all capture sessions.
  /// Called once when quitting, before destroying the windows.
  Future<void> prepareShutdown({required int nativeHandle});

  Stream<CaptureEvent> captureEvents(int sessionId);

  Future<PermissionState> permissionState();
  Future<void> requestPermission();
  Future<void> openPermissionSettings();

  /// Configures a DisplayWindow's native window (SPEC §9.5): always-on-top,
  /// transparent title bar + standard close button, capture exclusion and
  /// initial position. Call once per window before [startCapture].
  ///
  /// [allowFullScreen] (macOS only) makes the window a full-screen primary
  /// window so the green zoom button / ⌃⌘F enter native full screen.
  Future<void> setupDisplayWindow({
    required int nativeHandle,
    required WindowFrame initialFrame,
    bool allowFullScreen = false,
  });

  /// Windows only: hover state of the client-drawn close button.
  Stream<CloseHoverEvent> get closeHoverEvents;

  Future<DiagnosticsInfo> diagnostics();
}
