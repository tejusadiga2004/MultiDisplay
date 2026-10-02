// Flutter runs this before every test file in this directory.
//
// The app turns on Flutter's experimental windowing (`flutter config
// --enable-windowing`). With that flag on, the widgets binding creates the
// platform windowing owner while it initialises, and on Windows that owner looks
// up native engine functions (InternalFlutterWindows_WindowManager_Initialize)
// that do not exist in the headless `flutter_tester` process. Every widget test
// then fails to load.
//
// Unit and widget tests never open real native windows, so run them with the
// windowing feature off. The app itself is unaffected.
// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'dart:async';

import 'package:flutter/src/foundation/_features.dart' show isWindowingEnabled;

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  isWindowingEnabled = false;
  await testMain();
}
