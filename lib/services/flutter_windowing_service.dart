// This is the ONLY file that imports Flutter's experimental windowing API
// (SPEC C-7). The API is @internal and may break between Flutter versions; the
// app is pinned to the Flutter `main` checkout recorded in README.md.
// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'dart:async';
import 'dart:io' show Platform;

import 'package:display_capture_api/display_capture_api.dart';
import 'package:flutter/widgets.dart';
// ignore: unused_import
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_macos.dart';
import 'package:flutter/src/widgets/_window_win32.dart';

import '../ui/display_window/display_window_page.dart';
import '../ui/display_window/composite_window_page.dart';
import '../ui/theme.dart';
import 'window_service.dart';

const Size kControllerWindowSize = Size(640, 640);
const BoxConstraints kControllerWindowConstraints = BoxConstraints(
  minWidth: 640,
  minHeight: 480,
);
const BoxConstraints kDisplayWindowConstraints = BoxConstraints(
  minWidth: 320,
  minHeight: 180,
);
const Duration kOpenTimeout = Duration(seconds: 20);

class _OpenWindow {
  _OpenWindow(this.controller, this.entry, this.spec);

  final WindowController controller;
  final WindowEntry entry;
  final DisplayWindowSpec spec;
  Completer<void>? pendingReady = Completer<void>();
}

class _DisplayWindowDelegate with WindowControllerDelegate {
  _DisplayWindowDelegate(this._service);

  final FlutterWindowingService _service;
  String? displayId;

  @override
  void onWindowCloseRequested(WindowController controller) {
    // User pressed close / Alt+F4: unregister first, then destroy (R-5).
    final id = displayId;
    if (id != null) {
      _service.report(WindowClosed(id));
    } else {
      controller.destroy();
    }
  }

  @override
  void onWindowDestroyed() {
    final id = displayId;
    if (id != null) _service.report(WindowClosed(id)); // duplicate-safe
  }
}

class _ControllerWindowDelegate with WindowControllerDelegate {
  _ControllerWindowDelegate(this._onClosed);

  final Future<void> Function(int nativeHandle) _onClosed;
  bool _closing = false;

  @override
  void onWindowCloseRequested(WindowController controller) {
    if (_closing) return;
    _closing = true;
    final handle = Platform.isMacOS
        ? (controller as BaseWindowControllerMacOS).windowHandle.address
        : (controller as BaseWindowControllerWin32).windowHandle.address;
    unawaited(_onClosed(handle));
  }
}

class FlutterWindowingService implements WindowService {
  FlutterWindowingService({required this.onControllerClosed});

  /// Invoked once when closing the Display Controller is requested (D-8).
  /// Owns hiding the windows, cleaning up capture, and terminating the app.
  final Future<void> Function(int nativeHandle) onControllerClosed;

  final Map<String, _OpenWindow> _open = {};
  final StreamController<WindowEvent> _events =
      StreamController<WindowEvent>.broadcast();
  WindowRegistry? _registry;

  @override
  Stream<WindowEvent> get events => _events.stream;

  /// Builds the app root: a [WindowManager] holding the Display Controller window.
  Widget buildRoot({required Widget Function(BuildContext) controllerBuilder}) {
    WidgetsFlutterBinding.ensureInitialized();
    final controller = WindowController(
      size: kControllerWindowSize,
      constraints: kControllerWindowConstraints,
      title: 'Display Controller',
      delegate: _ControllerWindowDelegate(onControllerClosed),
    );
    return WindowManager(
      initialWindows: [
        WindowEntry(
          controller: controller,
          builder: (context) {
            // Idempotent: hands the registry to this service so DisplayWindows
            // can be added later.
            _registry = WindowRegistry.of(context);
            return controllerBuilder(context);
          },
        ),
      ],
    );
  }

  int _nativeHandle(WindowController c) {
    if (Platform.isWindows) {
      return (c as BaseWindowControllerWin32).windowHandle.address;
    }
    if (Platform.isMacOS) {
      return (c as BaseWindowControllerMacOS).windowHandle.address;
    }
    throw UnsupportedError('Only Windows and macOS are supported');
  }

  @override
  bool isOpen(String displayId) => _open.containsKey(displayId);

  @override
  Future<void> open(DisplayWindowSpec spec) async {
    final registry = _registry;
    if (registry == null) {
      throw StateError('Window registry is not attached yet');
    }
    final id = spec.displayId;
    if (_open.containsKey(id)) await close(id); // failed window, start fresh

    final delegate = _DisplayWindowDelegate(this)..displayId = id;
    final controller = WindowController(
      size: Size(spec.logicalSize.width, spec.logicalSize.height),
      constraints: kDisplayWindowConstraints,
      title: spec is CompositeWindowSpec
          ? 'Display layout'
          : spec.info.value.name,
      delegate: delegate,
    );
    final handle = _nativeHandle(controller);
    late final _OpenWindow record;
    final entry = WindowEntry(
      controller: controller,
      builder: (_) => WindowApp(
        title: spec.info.value.name,
        home: spec is CompositeWindowSpec
            ? CompositeWindowPage(spec: spec, nativeHandle: handle)
            : DisplayWindowPage(spec: spec, nativeHandle: handle),
      ),
    );
    record = _OpenWindow(controller, entry, spec);
    _open[id] = record;
    registry.register(entry);

    try {
      await record.pendingReady!.future.timeout(kOpenTimeout);
    } on TimeoutException {
      throw const CaptureError(
        CaptureErrorCode.internal,
        'Timed out while starting the display window',
      );
    }
  }

  @override
  void report(WindowEvent event) {
    final rec = _open[event.displayId];
    switch (event) {
      case WindowReady():
        final c = rec?.pendingReady;
        if (c != null && !c.isCompleted) c.complete();
        _events.add(event);
      case WindowFailed(:final error):
        final c = rec?.pendingReady;
        if (c != null && !c.isCompleted) c.completeError(error);
        _events.add(event);
      case WindowClosed(:final displayId):
        _finish(displayId);
    }
  }

  void _finish(String displayId) {
    final rec = _open.remove(displayId);
    if (rec == null) return;
    rec.spec.active = false;
    final pending = rec.pendingReady;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        const CaptureError(
          CaptureErrorCode.internal,
          'The window was closed before it finished starting',
        ),
      );
    }
    // The window must be unregistered before it is destroyed.
    _registry?.unregister(rec.entry);
    if (!rec.controller.isDestroyed) rec.controller.destroy();
    _events.add(WindowClosed(displayId));
  }

  @override
  Future<void> close(String displayId) async => _finish(displayId);

  @override
  Future<void> closeAll() async {
    for (final id in _open.keys.toList()) {
      _finish(id);
    }
  }

  @override
  void updateDisplay(DisplayInfo info) {
    _open[info.id]?.spec.info.value = info;
  }
}
