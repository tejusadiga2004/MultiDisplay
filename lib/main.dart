import 'dart:io' show exit;

import 'package:display_capture_api/display_capture_api.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/app_services.dart';
import 'services/flutter_windowing_service.dart';
import 'services/settings_store.dart';
import 'ui/controller/display_controller_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  final api = PluginDisplayCaptureApi();
  late final FlutterWindowingService windows;
  windows = FlutterWindowingService(
    // D-8: Controller closed -> all DisplayWindows closed, app quits.
    onControllerClosed: () async {
      await windows.closeAll();
      Future<void>.delayed(const Duration(milliseconds: 100), () => exit(0));
    },
  );

  runWidget(
    AppServices(
      api: api,
      windows: windows,
      settings: SharedPrefsSettingsStore(prefs),
      child: windows.buildRoot(
        controllerBuilder: (_) => const WindowApp(home: DisplayControllerPage()),
      ),
    ),
  );
}
