import 'dart:async';

import 'package:display_capture_api/display_capture_api.dart';
import 'package:display_controller/services/settings_store.dart';
import 'package:display_controller/services/app_services.dart';
import 'package:display_controller/services/window_service.dart';
import 'package:display_controller/ui/controller/display_controller_logic.dart';
import 'package:display_controller/ui/controller/display_controller_state.dart';
import 'package:display_controller/ui/controller/display_controller_page.dart';
import 'package:display_controller/ui/controller/display_row.dart';
import 'package:display_controller/ui/display_window/composite_window_page.dart';
import 'package:display_controller/ui/display_window/display_window_logic.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

DisplayInfo display(String id, {int x = 0, int y = 0}) => DisplayInfo(
  id: id,
  name: id,
  widthPx: 1920,
  heightPx: 1080,
  originX: x,
  originY: y,
);

class TrackingCaptureApi extends FakeDisplayCaptureApi {
  TrackingCaptureApi({required super.displays});
  final stopped = StreamController<int>.broadcast(sync: true);
  final owners = <int?>[];
  @override
  Future<CaptureSession> startCapture(
    String displayId, {
    CaptureOptions options = const CaptureOptions(),
  }) {
    owners.add(options.ownerWindowHandle);
    return super.startCapture(displayId, options: options);
  }

  @override
  Future<void> stopCapture(int sessionId) async {
    final stopping = super.stopCapture(sessionId);
    stopped.add(sessionId);
    await stopping;
  }
}

class TestWindows implements WindowService {
  final opened = <String, DisplayWindowSpec>{};
  final controller = StreamController<WindowEvent>.broadcast(sync: true);
  bool failOpen = false;
  @override
  Stream<WindowEvent> get events => controller.stream;
  @override
  bool isOpen(String id) => opened.containsKey(id);
  @override
  Future<void> open(DisplayWindowSpec spec) async {
    if (failOpen) throw StateError('Setup failed');
    opened[spec.displayId] = spec;
  }

  @override
  Future<void> close(String id) async {
    final spec = opened.remove(id);
    if (spec == null) return;
    spec.active = false;
    controller.add(WindowClosed(id));
  }

  @override
  Future<void> closeAll() async {
    for (final id in opened.keys.toList()) {
      await close(id);
    }
  }

  @override
  void updateDisplay(DisplayInfo info) {
    opened[info.id]?.info.value = info;
  }

  @override
  void report(WindowEvent event) => controller.add(event);
}

void main() {
  testWidgets(
    'launch height includes all rows and chrome and is reported once',
    (tester) async {
      tester.view.physicalSize = const Size(640, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final permission in [
        PermissionState.granted,
        PermissionState.denied,
      ]) {
        final windows = TestWindows();
        final api = FakeDisplayCaptureApi(
          displays: [for (var i = 0; i < 12; i++) display('$i')],
        )..permission = permission;
        final heights = <double>[];
        await tester.pumpWidget(
          AppServices(
            api: api,
            windows: windows,
            settings: MemorySettingsStore(),
            child: MaterialApp(
              home: DisplayControllerPage(
                onInitialContentHeight: (height) {
                  expect(tester.binding.schedulerPhase, SchedulerPhase.idle);
                  heights.add(height);
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final chromeHeight = 640 - tester.getSize(find.byType(ListView)).height;
        expect(heights, [chromeHeight + 12 * kDisplayRowHeight + 11]);
        if (permission == PermissionState.denied) {
          await tester.tap(find.byTooltip('Dismiss'));
          await tester.pumpAndSettle();
        }
        api.setDisplays([display('only')]);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Display layout'));
        await tester.pumpAndSettle();
        expect(heights, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await windows.controller.close();
      }
    },
  );

  testWidgets('permission banner is compact and dismissible at minimum size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final windows = TestWindows();
    final api = FakeDisplayCaptureApi(displays: [display('a')])
      ..permission = PermissionState.denied;
    await tester.pumpWidget(
      AppServices(
        api: api,
        windows: windows,
        settings: MemorySettingsStore(),
        child: const MaterialApp(home: DisplayControllerPage()),
      ),
    );
    await tester.pumpAndSettle();
    final banner = find.byKey(const ValueKey('permissionBanner'));
    expect(banner, findsOneWidget);
    // At most two text lines plus padding and margin (test fonts are wide).
    expect(tester.getSize(banner).height, lessThanOrEqualTo(80));
    final bannerBottom = tester.getBottomLeft(banner).dy;
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('viewModeToggle'))).dy,
      greaterThan(bannerBottom),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('windowModeToggle'))).dy,
      greaterThan(bannerBottom),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
    await tester.pumpWidget(const SizedBox());
    await windows.controller.close();
  });

  testWidgets('Controller exposes capture mode independently of List/Layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final windows = TestWindows();
    await tester.pumpWidget(
      AppServices(
        api: FakeDisplayCaptureApi(displays: [display('a')]),
        windows: windows,
        settings: MemorySettingsStore(),
        child: const MaterialApp(home: DisplayControllerPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final footer = find.byKey(const ValueKey('controllerFooter'));
    expect(
      find.descendant(of: footer, matching: find.text('1 display')),
      findsOneWidget,
    );
    expect(find.text('1 display'), findsOneWidget);
    expect(find.byTooltip('Separate windows'), findsOneWidget);
    expect(find.byTooltip('Single layout'), findsOneWidget);
    await tester.tap(find.byTooltip('Single layout'));
    await tester.pumpAndSettle();
    final mode = tester.widget<SegmentedButton<DisplayWindowMode>>(
      find.byKey(const ValueKey('windowModeToggle')),
    );
    expect(mode.selected, {DisplayWindowMode.composite});
    expect(mode.showSelectedIcon, isFalse);
    expect(windows.opened, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await windows.controller.close();
  });

  testWidgets(
    'composite page keeps existing sessions on layout edits and cleans up',
    (tester) async {
      final a = display('a');
      final b = display('b', x: 1920);
      final api = TrackingCaptureApi(displays: [a, b]);
      final windows = TestWindows();
      final spec = CompositeWindowSpec(
        display: a,
        displays: [a, b],
        initialFrame: const WindowFrame(0, 0, 640, 360),
        logicalSize: (width: 640, height: 360),
      );
      await tester.pumpWidget(
        AppServices(
          api: api,
          windows: windows,
          settings: MemorySettingsStore(),
          child: MaterialApp(
            home: CompositeWindowPage(spec: spec, nativeHandle: 99),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.activeSessions, hasLength(2));
      expect(
        api.calls.where((c) => c == 'setupDisplayWindow:99'),
        hasLength(1),
      );
      expect(api.calls, contains('allowFullScreen:99'));
      spec.displays.value = [a, display('b', x: -2000)];
      await tester.pumpAndSettle();
      expect(
        api.calls.where((c) => c.startsWith('startCapture:')),
        hasLength(2),
      );
      final stoppedOne = api.stopped.stream.first;
      spec.displays.value = [a];
      await tester.pumpAndSettle();
      await tester.pump();
      expect(find.byKey(const ValueKey('b')), findsNothing);
      await tester.runAsync(
        () => stoppedOne.timeout(const Duration(seconds: 2)),
      );
      expect(api.activeSessions, hasLength(1));
      spec.active = false;
      final stoppedLast = api.stopped.stream.first;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pump();
      await tester.runAsync(
        () => stoppedLast.timeout(const Duration(seconds: 2)),
      );
      expect(api.activeSessions, isEmpty);
      expect(api.owners, [99, 99]);
      await api.stopped.close();
      await windows.controller.close();
    },
  );

  test(
    'switching modes preserves selection and hotplug updates one window',
    () async {
      final a = display('a');
      final b = display('b', x: 2120, y: -300);
      final api = FakeDisplayCaptureApi(displays: [a, b]);
      final windows = TestWindows();
      final settings = MemorySettingsStore();
      final logic = DisplayControllerLogic(
        api: api,
        windows: windows,
        settings: settings,
      );
      addTearDown(() async {
        await logic.dispose();
        await windows.controller.close();
      });
      await logic.init();
      await logic.setEnabled('a', true);
      await logic.setEnabled('b', true);
      expect(windows.opened.keys, unorderedEquals(['a', 'b']));
      await logic.setWindowMode(DisplayWindowMode.composite);
      expect(windows.opened.keys, [compositeWindowId]);
      expect(settings.ids, {'a', 'b'});
      final spec = windows.opened[compositeWindowId]! as CompositeWindowSpec;
      expect(spec.displays.value.map((d) => d.id), ['a', 'b']);
      api.setDisplays([a, display('b', x: -2300, y: 100), display('c')]);
      await Future<void>.delayed(Duration.zero);
      expect(spec.displays.value.last.originX, -2300);
      expect(spec.displays.value.map((d) => d.id), ['a', 'b']);
      api.setDisplays([a, display('c')]);
      await Future<void>.delayed(Duration.zero);
      expect(spec.displays.value.map((d) => d.id), ['a']);
      expect(settings.ids, {'a'});
      await logic.setEnabled('c', true);
      expect(identical(spec, windows.opened[compositeWindowId]), isTrue);
      await logic.setWindowMode(DisplayWindowMode.separate);
      expect(windows.opened.keys, unorderedEquals(['a', 'c']));
      await logic.setWindowMode(DisplayWindowMode.composite);
      await windows.close(compositeWindowId);
      expect(logic.state.value.rows.every((r) => !r.enabled), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(settings.ids, isEmpty);
    },
  );

  test(
    'empty selection and composite setup failures leave no selected rows',
    () async {
      final api = FakeDisplayCaptureApi(displays: [display('a')]);
      final windows = TestWindows();
      final logic = DisplayControllerLogic(
        api: api,
        windows: windows,
        settings: MemorySettingsStore(),
      );
      addTearDown(() async {
        await logic.dispose();
        await windows.controller.close();
      });
      await logic.init();
      await logic.setWindowMode(DisplayWindowMode.composite);
      expect(windows.opened, isEmpty);
      final effects = <UiEffect>[];
      final sub = logic.effects.listen(effects.add);
      windows.failOpen = true;
      await logic.setEnabled('a', true);
      await Future<void>.delayed(Duration.zero);
      expect(logic.state.value.rows.single.enabled, isFalse);
      expect(effects, hasLength(1));
      await sub.cancel();
      windows.failOpen = false;
      await logic.setEnabled('a', true);
      await logic.setEnabled('a', false);
      expect(windows.opened, isEmpty);
    },
  );

  test(
    'embedded capture shares owner handle and does not own window lifecycle',
    () async {
      final api = FakeDisplayCaptureApi(displays: [display('a'), display('b')]);
      final windows = TestWindows();
      final events = <WindowEvent>[];
      final sub = windows.events.listen(events.add);
      final logics = [
        for (final id in ['a', 'b'])
          DisplayWindowLogic(
            api: api,
            windows: windows,
            nativeHandle: 99,
            spec: EmbeddedDisplaySpec(
              display: display(id),
              initialFrame: const WindowFrame(0, 0, 640, 360),
              logicalSize: (width: 640, height: 360),
            ),
          ),
      ];
      for (final logic in logics) {
        await logic.init();
      }
      expect(api.activeSessions, hasLength(2));
      expect(
        api.calls.where((c) => c.startsWith('setupDisplayWindow')),
        isEmpty,
      );
      await logics.first.dispose();
      expect(api.activeSessions, hasLength(1));
      expect(events, isEmpty);
      await logics.last.dispose();
      expect(api.activeSessions, isEmpty);
      await sub.cancel();
      await windows.controller.close();
    },
  );

  testWidgets(
    'canvas preserves offsets and gaps and responds to layout changes',
    (tester) async {
      Future<void> render(List<DisplayInfo> displays) => tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 800,
            height: 600,
            child: CompositeCanvas(
              displays: displays,
              platform: TargetPlatform.windows,
              tileBuilder: (d) =>
                  ColoredBox(color: Colors.blue, child: Text(d.name)),
            ),
          ),
        ),
      );
      await render([display('a', x: -1920), display('b', x: 200, y: -300)]);
      final a = tester.getRect(find.byKey(const ValueKey('a')));
      final b = tester.getRect(find.byKey(const ValueKey('b')));
      expect(b.left - a.right, closeTo(a.width * 200 / 1920, 0.01));
      expect(a.top - b.top, closeTo(a.width * 300 / 1920, 0.01));
      await render([display('a'), display('b', x: -2120)]);
      expect(
        tester.getRect(find.byKey(const ValueKey('b'))).right,
        lessThan(tester.getRect(find.byKey(const ValueKey('a'))).left),
      );
      await render([]);
      expect(find.byType(Positioned), findsNothing);
    },
  );
}
