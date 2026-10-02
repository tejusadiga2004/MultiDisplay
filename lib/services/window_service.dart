import 'dart:async';

import 'package:display_capture_api/display_capture_api.dart';
import 'package:flutter/foundation.dart';

/// Everything needed to create one DisplayWindow (SPEC §9.3).
class DisplayWindowSpec {
  DisplayWindowSpec({
    required DisplayInfo display,
    required this.initialFrame,
    required this.logicalSize,
  }) : info = ValueNotifier<DisplayInfo>(display);

  String get displayId => info.value.id;

  /// Live info of the mirrored display (name/resolution may change).
  final ValueNotifier<DisplayInfo> info;

  /// Position (and nominal size) in physical px, virtual-desktop coordinates.
  final WindowFrame initialFrame;

  /// Initial content size in logical px, passed to the window constructor.
  final ({double width, double height}) logicalSize;

  // Invalidated before unregistering so late async capture callbacks cannot
  // change the selection or close a replacement window with the same ID.
  bool active = true;
  bool get managesWindow => true;
}

const compositeWindowId = 'composite:desktop';

class CompositeWindowSpec extends DisplayWindowSpec {
  CompositeWindowSpec({
    required super.display,
    required super.initialFrame,
    required super.logicalSize,
    required List<DisplayInfo> displays,
  }) : displays = ValueNotifier(List<DisplayInfo>.unmodifiable(displays));

  final ValueNotifier<List<DisplayInfo>> displays;

  @override
  String get displayId => compositeWindowId;
}

class EmbeddedDisplaySpec extends DisplayWindowSpec {
  EmbeddedDisplaySpec({
    required super.display,
    required super.initialFrame,
    required super.logicalSize,
  });

  @override
  bool get managesWindow => false;
}

sealed class WindowEvent {
  const WindowEvent(this.displayId);
  final String displayId;
}

/// The window finished setup and capture is running.
class WindowReady extends WindowEvent {
  const WindowReady(super.displayId);
}

/// Setup or capture failed. The window stays open showing the error.
class WindowFailed extends WindowEvent {
  const WindowFailed(super.displayId, this.error);
  final CaptureError error;
}

/// The window is gone (closed by user, programmatically, or display lost).
class WindowClosed extends WindowEvent {
  const WindowClosed(super.displayId);
}

abstract class WindowService {
  /// Creates the DisplayWindow. Completes when its logic reports ready; throws
  /// the [CaptureError] if it reports failure (the window stays open).
  /// If a window for the same display is already open it is closed first.
  Future<void> open(DisplayWindowSpec spec);

  Future<void> close(String displayId);
  Future<void> closeAll();
  bool isOpen(String displayId);

  /// Pushes a changed [DisplayInfo] (name, resolution) to an open window.
  void updateDisplay(DisplayInfo info);

  /// Called by window logic to report lifecycle changes.
  void report(WindowEvent event);

  Stream<WindowEvent> get events;
}
