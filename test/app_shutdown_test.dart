import 'dart:async';

import 'package:display_capture_api/display_capture_api.dart';
import 'package:display_controller/services/app_shutdown.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'composite_window_test.dart' show TestWindows;

class ShutdownApi extends FakeDisplayCaptureApi {
  final prepared = Completer<void>();
  final entered = Completer<void>();

  @override
  Future<void> prepareShutdown({required int nativeHandle}) {
    calls.add('prepareShutdown:$nativeHandle');
    entered.complete();
    return prepared.future;
  }
}

class ShutdownWindows extends TestWindows {
  bool closed = false;

  @override
  Future<void> closeAll() async {
    closed = true;
  }
}

void main() {
  test(
    'waits for native capture cleanup before closing windows and quitting',
    () async {
      final api = ShutdownApi();
      final windows = ShutdownWindows();
      var quit = false;
      final shutdown = shutdownApp(
        api: api,
        windows: windows,
        nativeHandle: 42,
        quit: () => quit = true,
      );
      await api.entered.future;
      expect(api.calls, ['prepareShutdown:42']);
      expect(windows.closed, isFalse);
      expect(quit, isFalse);
      api.prepared.complete();
      await shutdown;
      expect(windows.closed, isTrue);
      expect(quit, isTrue);
      await windows.controller.close();
    },
  );

  test('logs cleanup errors but still closes windows and quits', () async {
    final api = ShutdownApi();
    final windows = ShutdownWindows();
    final messages = <String?>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => messages.add(message);
    addTearDown(() => debugPrint = previous);
    var quit = false;
    final shutdown = shutdownApp(
      api: api,
      windows: windows,
      nativeHandle: 42,
      quit: () => quit = true,
    );
    api.prepared.completeError(StateError('Stop failed'));
    await shutdown;
    expect(windows.closed, isTrue);
    expect(quit, isTrue);
    expect(messages.single, contains('Stop failed'));
    await windows.controller.close();
  });

  test('quits and logs when native cleanup exceeds the deadline', () async {
    final api = ShutdownApi();
    final windows = ShutdownWindows();
    final messages = <String?>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => messages.add(message);
    addTearDown(() => debugPrint = previous);
    var quit = false;
    await shutdownApp(
      api: api,
      windows: windows,
      nativeHandle: 42,
      quit: () => quit = true,
      timeout: const Duration(milliseconds: 10),
    );
    expect(quit, isTrue);
    expect(messages.single, contains('TimeoutException'));
    api.prepared.complete();
    await Future<void>.delayed(Duration.zero);
    await windows.controller.close();
  });
}
