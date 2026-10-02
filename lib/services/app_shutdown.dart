import 'dart:async';

import 'package:display_capture_api/display_capture_api.dart';
import 'package:flutter/foundation.dart';

import 'window_service.dart';

Future<void> shutdownApp({
  required DisplayCaptureApi api,
  required WindowService windows,
  required int nativeHandle,
  required VoidCallback quit,
  Duration timeout = const Duration(seconds: 3),
}) async {
  try {
    await (() async {
      try {
        await api.prepareShutdown(nativeHandle: nativeHandle);
      } finally {
        await windows.closeAll();
      }
    })().timeout(timeout);
  } on Object catch (error, stack) {
    debugPrint('Application shutdown failed: $error\n$stack');
  } finally {
    quit();
  }
}
