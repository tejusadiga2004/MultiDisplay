import 'package:display_capture_api/display_capture_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:display_controller/services/app_services.dart';
import 'package:display_controller/services/settings_store.dart';
import 'package:display_controller/services/window_service.dart';

class _UnusedWindowService implements WindowService {
  @override
  Stream<WindowEvent> get events => const Stream.empty();

  @override
  bool isOpen(String displayId) => false;

  @override
  Future<void> open(DisplayWindowSpec spec) =>
      throw StateError('This widget test must not open native windows');

  @override
  Future<void> close(String displayId) async {}

  @override
  Future<void> closeAll() async {}

  @override
  void updateDisplay(DisplayInfo info) {}

  @override
  void report(WindowEvent event) {}
}

void main() {
  testWidgets('AppServices can host a simple scaffold', (
    WidgetTester tester,
  ) async {
    final api = FakeDisplayCaptureApi(
      displays: const [
        DisplayInfo(
          id: 'mac:demo-0',
          name: 'Demo Display',
          widthPx: 1920,
          heightPx: 1080,
        ),
      ],
    );
    final windows = _UnusedWindowService();

    await tester.pumpWidget(
      AppServices(
        api: api,
        windows: windows,
        settings: MemorySettingsStore(),
        child: const MaterialApp(
          home: Scaffold(body: Center(child: Text('ok'))),
        ),
      ),
    );

    expect(find.text('ok'), findsOneWidget);
  });
}
