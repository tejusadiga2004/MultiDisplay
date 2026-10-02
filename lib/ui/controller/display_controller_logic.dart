import 'dart:async';

import 'package:display_capture_api/display_capture_api.dart';
import 'package:flutter/foundation.dart';

import '../../services/initial_frame.dart';
import '../../services/settings_store.dart';
import '../../services/window_service.dart';
import 'display_controller_state.dart';

/// Logic of the Display Controller window (SPEC §9.2). Plain Dart, no widgets.
class DisplayControllerLogic {
  DisplayControllerLogic({
    required this.api,
    required this.windows,
    required this.settings,
  });

  final DisplayCaptureApi api;
  final WindowService windows;
  final SettingsStore settings;

  final ValueNotifier<DisplayControllerState> state = ValueNotifier(
    const DisplayControllerState(),
  );

  final StreamController<UiEffect> _effects =
      StreamController<UiEffect>.broadcast();
  Stream<UiEffect> get effects => _effects.stream;

  StreamSubscription<List<DisplayInfo>>? _displaysSub;
  StreamSubscription<WindowEvent>? _windowSub;

  /// displayId -> displayId of the display its window was placed on (cascade).
  final Map<String, String> _targets = {};
  bool _disposed = false;
  CompositeWindowSpec? _composite;

  DisplayControllerState get _s => state.value;
  void _set(DisplayControllerState s) {
    if (!_disposed) state.value = s;
  }

  Future<void> init() async {
    _windowSub = windows.events.listen(_onWindowEvent);
    try {
      final permission = await api.permissionState();
      final displays = await api.listDisplays();
      if (_disposed) return;
      _set(
        DisplayControllerState(
          status: ViewStatus.ready,
          permission: permission,
          rows: [for (final d in displays) DisplayRowState(info: d)],
        ),
      );
      _displaysSub = api.displaysChanged.listen(_onDisplaysChanged);

      // D-1: restore only displays that were On last time and are connected.
      final saved = settings.loadEnabledIds();
      final present = {for (final d in displays) d.id};
      final keep = saved.intersection(present);
      if (keep.length != saved.length) await settings.saveEnabledIds(keep);
      for (final d in displays) {
        if (keep.contains(d.id) && d.isCapturable) {
          await setEnabled(d.id, true);
        }
      }
    } on Object catch (e) {
      if (_disposed) return;
      _set(
        DisplayControllerState(
          status: ViewStatus.error,
          errorMessage: e is CaptureError ? e.message : e.toString(),
        ),
      );
    }
  }

  Future<void> retry() async {
    _set(const DisplayControllerState());
    await _displaysSub?.cancel();
    _displaysSub = null;
    await init();
  }

  int _indexOf(String id) => _s.rows.indexWhere((r) => r.info.id == id);

  void _updateRow(String id, DisplayRowState Function(DisplayRowState) f) {
    final i = _indexOf(id);
    if (i < 0) return;
    final rows = [..._s.rows];
    rows[i] = f(rows[i]);
    _set(_s.copyWith(rows: rows));
  }

  Future<void> _persist() => settings.saveEnabledIds({
    for (final r in _s.rows)
      if (r.enabled) r.info.id,
  });

  Future<void> setEnabled(String id, bool enabled) => _setEnabled(id, enabled);

  Future<void> _setEnabled(
    String id,
    bool enabled, {
    bool restoring = false,
  }) async {
    if (_s.switchingMode && !restoring) return;
    final i = _indexOf(id);
    if (i < 0) return;
    final row = _s.rows[i];
    if (row.busy) return;

    if (_s.windowMode == DisplayWindowMode.composite) {
      if (enabled && !row.info.isCapturable) return;
      _updateRow(id, (r) => r.copyWith(enabled: enabled));
      await _persist();
      await _syncComposite();
      return;
    }

    if (!enabled) {
      if (!row.enabled && !windows.isOpen(id)) return;
      _updateRow(id, (r) => r.copyWith(enabled: false, busy: false));
      _targets.remove(id);
      await _persist();
      await windows.close(id);
      return;
    }

    if (row.enabled || !row.info.isCapturable) return;
    _updateRow(id, (r) => r.copyWith(busy: true));
    try {
      final displays = [for (final r in _s.rows) r.info];
      final source = row.info;
      final target = pickTargetDisplay(source, displays);
      final openOnTarget = _targets.entries
          .where((e) => e.key != id && e.value == target.id)
          .length;
      final placement = computeInitialPlacement(
        source: source,
        displays: displays,
        openOnTarget: openOnTarget,
      );
      _targets[id] = placement.targetDisplayId;
      await windows.open(
        DisplayWindowSpec(
          display: source,
          initialFrame: placement.frame,
          logicalSize: (
            width: placement.logicalWidth,
            height: placement.logicalHeight,
          ),
        ),
      );
      _updateRow(id, (r) => r.copyWith(enabled: true, busy: false));
      await _persist();
    } on Object catch (e) {
      _targets.remove(id);
      _updateRow(id, (r) => r.copyWith(enabled: false, busy: false));
      final msg = e is CaptureError ? e.message : e.toString();
      _effects.add(
        ShowSnackBar("Couldn't open window for ${row.info.name}: $msg"),
      );
    }
  }

  void _onWindowEvent(WindowEvent e) {
    if (_s.switchingMode) return;
    if (e.displayId == compositeWindowId) {
      if (e is WindowClosed) {
        _composite = null;
        _set(
          _s.copyWith(
            rows: [
              for (final row in _s.rows)
                row.copyWith(enabled: false, busy: false),
            ],
          ),
        );
        unawaited(_persist());
      }
      return;
    }
    if (_s.windowMode == DisplayWindowMode.composite) return;
    switch (e) {
      case WindowClosed(:final displayId):
        // R-5: closing a DisplayWindow by any means turns the toggle Off.
        _targets.remove(displayId);
        _updateRow(displayId, (r) => r.copyWith(enabled: false, busy: false));
        unawaited(_persist());
      case WindowFailed(:final displayId):
        // While opening, setEnabled() reports the failure itself.
        final i = _indexOf(displayId);
        if (i >= 0 && !_s.rows[i].busy) {
          _updateRow(displayId, (r) => r.copyWith(enabled: false));
          unawaited(_persist());
        }
      case WindowReady(:final displayId):
        // A Retry inside a failed window succeeded.
        final i = _indexOf(displayId);
        if (i >= 0 && !_s.rows[i].busy && !_s.rows[i].enabled) {
          _updateRow(displayId, (r) => r.copyWith(enabled: true));
          unawaited(_persist());
        }
    }
  }

  void _onDisplaysChanged(List<DisplayInfo> list) {
    final old = {for (final r in _s.rows) r.info.id: r};
    final incoming = {for (final d in list) d.id: d};

    for (final id in old.keys) {
      if (!incoming.containsKey(id)) {
        _targets.remove(id);
        if (_s.windowMode == DisplayWindowMode.separate) {
          unawaited(windows.close(id)); // D-7: window closes with the display
        }
      }
    }

    final rows = <DisplayRowState>[
      for (final d in list)
        if (old[d.id] case final prev?)
          prev.copyWith(info: d)
        else
          DisplayRowState(info: d),
    ];
    _set(_s.copyWith(rows: rows));
    unawaited(_persist()); // drops removed ids (D-7)

    for (final d in list) {
      if (old[d.id] != null && old[d.id]!.info != d) windows.updateDisplay(d);
    }
    if (_s.windowMode == DisplayWindowMode.composite) {
      unawaited(_syncComposite());
    }
  }

  Future<void> setWindowMode(DisplayWindowMode mode) async {
    if (_s.windowMode == mode ||
        _s.switchingMode ||
        _s.rows.any((r) => r.busy)) {
      return;
    }
    final selected = {
      for (final row in _s.rows)
        if (row.enabled) row.info.id,
    };
    _set(_s.copyWith(switchingMode: true));
    try {
      await windows.closeAll();
      _targets.clear();
      _composite = null;
      _set(_s.copyWith(windowMode: mode));
      if (mode == DisplayWindowMode.composite) {
        await _syncComposite();
      } else {
        _set(
          _s.copyWith(
            rows: [for (final row in _s.rows) row.copyWith(enabled: false)],
          ),
        );
        for (final id in selected) {
          await _setEnabled(id, true, restoring: true);
        }
      }
    } on Object catch (error) {
      _effects.add(ShowSnackBar("Couldn't switch display window mode: $error"));
    } finally {
      _set(_s.copyWith(switchingMode: false));
      await _persist();
    }
  }

  Future<void> _syncComposite() async {
    final selected = [
      for (final row in _s.rows)
        if (row.enabled) row.info,
    ];
    if (selected.isEmpty) {
      _composite = null;
      await windows.close(compositeWindowId);
      return;
    }
    if (_composite != null) {
      _composite!.displays.value = List.unmodifiable(selected);
      return;
    }
    final placement = computeInitialPlacement(
      source: selected.first,
      displays: [for (final row in _s.rows) row.info],
      openOnTarget: 0,
    );
    final spec = CompositeWindowSpec(
      display: selected.first,
      displays: selected,
      initialFrame: placement.frame,
      logicalSize: (
        width: placement.logicalWidth,
        height: placement.logicalHeight,
      ),
    );
    _composite = spec;
    try {
      await windows.open(spec);
    } on Object catch (error) {
      if (identical(_composite, spec)) {
        _composite = null;
        await windows.close(compositeWindowId);
        _set(
          _s.copyWith(
            rows: [
              for (final row in _s.rows)
                row.copyWith(enabled: false, busy: false),
            ],
          ),
        );
        await _persist();
        _effects.add(
          ShowSnackBar("Couldn't open display layout window: $error"),
        );
      }
    }
  }

  Future<void> requestPermission() async {
    await api.requestPermission();
    _set(_s.copyWith(permission: await api.permissionState()));
  }

  Future<void> openPermissionSettings() => api.openPermissionSettings();

  /// Controller closed (D-8): close every DisplayWindow.
  Future<void> shutdown() async {
    await windows.closeAll();
  }

  Future<void> dispose() async {
    _disposed = true;
    await _displaysSub?.cancel();
    await _windowSub?.cancel();
    await _effects.close();
  }
}
