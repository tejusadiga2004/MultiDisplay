import 'dart:async';

import 'display_capture_api.dart';
import 'models.dart';

/// In-memory implementation for tests and UI development without native code.
class FakeDisplayCaptureApi implements DisplayCaptureApi {
  FakeDisplayCaptureApi({List<DisplayInfo> displays = const []})
      : _displays = List.of(displays);

  List<DisplayInfo> _displays;
  final _changes = StreamController<List<DisplayInfo>>.broadcast();
  final _sessions = <int, _FakeSession>{};
  int _nextSession = 1;

  /// Display ids for which [startCapture] throws [startError].
  CaptureError? startError;
  PermissionState permission = PermissionState.granted;
  final List<String> calls = [];
  final _hover = StreamController<CloseHoverEvent>.broadcast();

  List<int> get activeSessions => _sessions.keys.toList();

  void setDisplays(List<DisplayInfo> list) {
    _displays = List.of(list);
    _changes.add(List.of(_displays));
  }

  void emit(int sessionId, CaptureEvent e) => _sessions[sessionId]?.events.add(e);

  @override
  Future<List<DisplayInfo>> listDisplays() async {
    calls.add('listDisplays');
    return List.of(_displays);
  }

  @override
  Stream<List<DisplayInfo>> get displaysChanged => _changes.stream;

  @override
  Future<CaptureSession> startCapture(String displayId,
      {CaptureOptions options = const CaptureOptions()}) async {
    calls.add('startCapture:$displayId');
    final err = startError;
    if (err != null) throw err;
    final d = _displays.firstWhere((d) => d.id == displayId,
        orElse: () => throw const CaptureError(
            CaptureErrorCode.displayNotFound, 'Display not found'));
    final id = _nextSession++;
    _sessions[id] = _FakeSession();
    return CaptureSession(
        sessionId: id, textureId: 1000 + id, widthPx: d.widthPx, heightPx: d.heightPx);
  }

  @override
  Future<void> stopCapture(int sessionId) async {
    calls.add('stopCapture:$sessionId');
    await _sessions.remove(sessionId)?.events.close();
  }

  @override
  Stream<CaptureEvent> captureEvents(int sessionId) =>
      _sessions[sessionId]?.events.stream ?? const Stream.empty();

  @override
  Future<PermissionState> permissionState() async => permission;

  @override
  Future<void> requestPermission() async => calls.add('requestPermission');

  @override
  Future<void> openPermissionSettings() async => calls.add('openPermissionSettings');

  @override
  Future<void> setupDisplayWindow({
    required int nativeHandle,
    required WindowFrame initialFrame,
  }) async =>
      calls.add('setupDisplayWindow:$nativeHandle');

  @override
  Stream<CloseHoverEvent> get closeHoverEvents => _hover.stream;

  void emitHover(int handle, bool hot) =>
      _hover.add(CloseHoverEvent(nativeHandle: handle, hot: hot));

  @override
  Future<DiagnosticsInfo> diagnostics() async => const DiagnosticsInfo(
      renderPath: 'fake', backend: 'fake', gpuName: 'fake', driver: 'fake');
}

class _FakeSession {
  final events = StreamController<CaptureEvent>.broadcast();
}
