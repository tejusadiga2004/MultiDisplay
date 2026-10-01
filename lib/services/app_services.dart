import 'package:display_capture_api/display_capture_api.dart';
import 'package:flutter/widgets.dart';

import 'settings_store.dart';
import 'window_service.dart';

/// Root-level dependency holder (SPEC §9.0). Sits above the window manager so
/// every window's view tree can reach it.
class AppServices extends InheritedWidget {
  const AppServices({
    super.key,
    required this.api,
    required this.windows,
    required this.settings,
    required super.child,
  });

  final DisplayCaptureApi api;
  final WindowService windows;
  final SettingsStore settings;

  static AppServices of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<AppServices>();
    assert(s != null, 'No AppServices found in context');
    return s!;
  }

  @override
  bool updateShouldNotify(AppServices old) =>
      api != old.api || windows != old.windows || settings != old.settings;
}
