import 'dart:async';

import 'package:display_capture_api/display_capture_api.dart';
import 'package:flutter/foundation.dart';

import '../../services/window_service.dart';
import 'display_window_state.dart';

/// Logic of one DisplayWindow (SPEC §9.4). Plain Dart, no widgets.
class DisplayWindowLogic {
  DisplayWindowLogic({
    required this.api,
    required this.windows,
    required this.spec,
    required this.nativeHandle,
  }) : state = ValueNotifier(
         DisplayWindowState(
           name: spec.info.value.name,
           widthPx: spec.info.value.widthPx,
           heightPx: spec.info.value.heightPx,
         ),
       );

  final DisplayCaptureApi api;
  final WindowService windows;
  final DisplayWindowSpec spec;
  final int nativeHandle;

  final ValueNotifier<DisplayWindowState> state;

  CaptureSession? _session;
  StreamSubscription<CaptureEvent>? _eventSub;
  bool _disposed = false;
  bool _setupDone = false;

  String get displayId => spec.displayId;
  DisplayWindowState get _s => state.value;

  void _set(DisplayWindowState s) {
    if (!_disposed) state.value = s;
  }

  Future<void> init() async {
    debugPrint('DBG DisplayWindowLogic.init $displayId handle=$nativeHandle');
    spec.info.addListener(_onInfoChanged);
    await _startAll();
  }

  Future<void> retry() async {
    await _stopSession();
    _set(_s.copyWith(status: DisplayWindowStatus.starting, clearError: true));
    await _startAll();
  }

  Future<void> _startAll() async {
    try {
      if (!_setupDone && spec.managesWindow) {
        await api.setupDisplayWindow(
          nativeHandle: nativeHandle,
          initialFrame: spec.initialFrame,
        );
        _setupDone = true;
      }
      final session = await api.startCapture(
        displayId,
        options: CaptureOptions(ownerWindowHandle: nativeHandle),
      );
      if (_disposed) {
        await api.stopCapture(session.sessionId);
        return;
      }
      _session = session;
      _eventSub = api.captureEvents(session.sessionId).listen(_onCaptureEvent);
      _set(
        _s.copyWith(
          status: DisplayWindowStatus.running,
          textureId: session.textureId,
          widthPx: session.widthPx,
          heightPx: session.heightPx,
          clearError: true,
        ),
      );
      if (spec.managesWindow && spec.active) {
        windows.report(WindowReady(displayId));
      }
    } on Object catch (e) {
      _fail(
        e is CaptureError ? e : CaptureError(CaptureErrorCode.internal, '$e'),
      );
    }
  }

  void _fail(CaptureError error) {
    _set(_s.copyWith(status: DisplayWindowStatus.failed, error: error));
    if (spec.managesWindow && spec.active) {
      windows.report(WindowFailed(displayId, error));
    }
  }

  void _onCaptureEvent(CaptureEvent e) {
    switch (e) {
      case FrameSizeChanged(:final widthPx, :final heightPx):
        _set(_s.copyWith(widthPx: widthPx, heightPx: heightPx));
      case DisplayLost():
        if (spec.managesWindow) {
          _set(_s.copyWith(status: DisplayWindowStatus.closed));
          if (spec.active) unawaited(windows.close(displayId));
        } else {
          unawaited(_stopSession());
          _fail(
            const CaptureError(
              CaptureErrorCode.internal,
              'Display disconnected',
            ),
          );
        }
      case CaptureFailed(:final error):
        unawaited(_stopSession());
        _fail(error);
      case CaptureStalled() || CaptureResumed():
        break; // reserved (SPEC §7.2): no UI for static content
    }
  }

  void _onInfoChanged() {
    final info = spec.info.value;
    _set(_s.copyWith(name: info.name));
    // Resolution follows the session's FrameSizeChanged; before the session
    // exists, use the display's value.
    if (_session == null) {
      _set(_s.copyWith(widthPx: info.widthPx, heightPx: info.heightPx));
    }
  }

  Future<void> _stopSession() async {
    final s = _session;
    _session = null;
    await _eventSub?.cancel();
    _eventSub = null;
    if (s != null) {
      try {
        await api.stopCapture(s.sessionId);
      } on Object catch (error) {
        debugPrint('Could not stop capture for $displayId: $error');
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    spec.info.removeListener(_onInfoChanged);
    try {
      await _stopSession();
    } finally {
      // The event MUST be reported even if stopCapture failed.
      if (spec.managesWindow && spec.active) {
        windows.report(WindowClosed(displayId));
      }
    }
  }
}
