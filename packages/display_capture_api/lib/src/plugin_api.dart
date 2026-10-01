import 'dart:async';

import 'package:flutter/services.dart';

import 'display_capture_api.dart';
import 'models.dart';

/// Channel names (SPEC §6.3). Identical on every OS.
const String kMethodChannelName = 'com.virtualmonitor/display_capture';
const String kDisplaysChannelName = 'com.virtualmonitor/display_capture/displays';
const String kChromeChannelName = 'com.virtualmonitor/display_capture/chrome';
String sessionChannelName(int sessionId) =>
    'com.virtualmonitor/display_capture/session/$sessionId';

/// [DisplayCaptureApi] backed by the native `display_capture` plugin.
class PluginDisplayCaptureApi implements DisplayCaptureApi {
  PluginDisplayCaptureApi({
    MethodChannel? method,
    EventChannel? displays,
    EventChannel? chrome,
    EventChannel Function(int sessionId)? sessionChannel,
  })  : _method = method ?? const MethodChannel(kMethodChannelName),
        _displays = displays ?? const EventChannel(kDisplaysChannelName),
        _chrome = chrome ?? const EventChannel(kChromeChannelName),
        _sessionChannel =
            sessionChannel ?? ((id) => EventChannel(sessionChannelName(id)));

  final MethodChannel _method;
  final EventChannel _displays;
  final EventChannel _chrome;
  final EventChannel Function(int) _sessionChannel;

  Future<T> _invoke<T>(String name, [Object? args]) async {
    try {
      final T? r = await _method.invokeMethod<T>(name, args);
      return r as T;
    } on PlatformException catch (e) {
      throw CaptureError(CaptureErrorCode.fromWire(e.code), e.message ?? e.code);
    }
  }

  @override
  Future<List<DisplayInfo>> listDisplays() async {
    final raw = await _invoke<List<Object?>>('listDisplays');
    return raw
        .map((e) => DisplayInfo.fromMap(e! as Map<Object?, Object?>))
        .toList(growable: false);
  }

  // The native side keeps a single sink per EventChannel, so every listener
  // MUST share one platform subscription: cache the broadcast streams.
  @override
  late final Stream<List<DisplayInfo>> displaysChanged =
      _displays.receiveBroadcastStream().map((event) => (event as List<Object?>)
          .map((e) => DisplayInfo.fromMap(e! as Map<Object?, Object?>))
          .toList(growable: false));

  @override
  Future<CaptureSession> startCapture(String displayId,
      {CaptureOptions options = const CaptureOptions()}) async {
    final m = await _invoke<Map<Object?, Object?>>('startCapture', {
      'displayId': displayId,
      'maxWidthPx': options.maxWidthPx,
      'maxHeightPx': options.maxHeightPx,
      'fps': options.fps,
      'showCursor': options.showCursor,
      'ownerWindowHandle': options.ownerWindowHandle,
    });
    return CaptureSession(
      sessionId: (m['sessionId']! as num).toInt(),
      textureId: (m['textureId']! as num).toInt(),
      widthPx: (m['widthPx']! as num).toInt(),
      heightPx: (m['heightPx']! as num).toInt(),
    );
  }

  @override
  Future<void> stopCapture(int sessionId) =>
      _invoke<void>('stopCapture', {'sessionId': sessionId});

  @override
  Stream<CaptureEvent> captureEvents(int sessionId) => _sessionChannel(sessionId)
      .receiveBroadcastStream()
      .map((e) => _parseEvent(e as Map<Object?, Object?>))
      .where((e) => e != null)
      .cast<CaptureEvent>();

  static CaptureEvent? _parseEvent(Map<Object?, Object?> m) => switch (m['type']) {
        'frameSize' => FrameSizeChanged(
            (m['widthPx']! as num).toInt(), (m['heightPx']! as num).toInt()),
        'stalled' => const CaptureStalled(),
        'resumed' => const CaptureResumed(),
        'displayLost' => const DisplayLost(),
        'failed' => CaptureFailed(CaptureError(
            CaptureErrorCode.fromWire(m['code'] as String?),
            m['message'] as String? ?? '')),
        _ => null,
      };

  @override
  Future<PermissionState> permissionState() async {
    final s = await _invoke<String>('permissionState');
    return switch (s) {
      'granted' => PermissionState.granted,
      'denied' => PermissionState.denied,
      _ => PermissionState.notDetermined,
    };
  }

  @override
  Future<void> requestPermission() => _invoke<void>('requestPermission');

  @override
  Future<void> openPermissionSettings() => _invoke<void>('openPermissionSettings');

  @override
  Future<void> setupDisplayWindow({
    required int nativeHandle,
    required WindowFrame initialFrame,
  }) =>
      _invoke<void>('setupDisplayWindow', {
        'nativeHandle': nativeHandle,
        'x': initialFrame.x,
        'y': initialFrame.y,
        'width': initialFrame.width,
        'height': initialFrame.height,
      });

  @override
  late final Stream<CloseHoverEvent> closeHoverEvents =
      _chrome.receiveBroadcastStream().map((e) {
        final m = e as Map<Object?, Object?>;
        return CloseHoverEvent(
            nativeHandle: (m['nativeHandle']! as num).toInt(),
            hot: m['hot']! as bool);
      });

  @override
  Future<DiagnosticsInfo> diagnostics() async => DiagnosticsInfo.fromMap(
      await _invoke<Map<Object?, Object?>>('diagnostics'));
}
