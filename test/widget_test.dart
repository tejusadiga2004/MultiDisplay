// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:display_capture_api/display_capture_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:display_controller/services/app_services.dart';
import 'package:display_controller/services/flutter_windowing_service.dart';
import 'package:display_controller/services/settings_store.dart';

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
    final windows = FlutterWindowingService(onControllerClosed: () async {});

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
