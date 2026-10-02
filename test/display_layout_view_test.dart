import 'package:display_capture_api/display_capture_api.dart';
import 'package:display_controller/ui/controller/display_controller_state.dart';
import 'package:display_controller/ui/controller/display_layout_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DisplayInfo _d(
  String id,
  int x,
  int y,
  int w,
  int h, {
  double scale = 1,
  DisplayKind kind = DisplayKind.physical,
  CaptureStatus status = CaptureStatus.available,
}) => DisplayInfo(
  id: id,
  name: 'Display $id',
  widthPx: w,
  heightPx: h,
  originX: x,
  originY: y,
  scaleFactor: scale,
  refreshRateHz: 60,
  kind: kind,
  captureStatus: status,
);

void main() {
  group('displayLayoutRect', () {
    test('Windows uses physical virtual-desktop rects as-is', () {
      expect(
        displayLayoutRect(
          _d('a', -1920, 100, 1920, 1080),
          platform: TargetPlatform.windows,
        ),
        const Rect.fromLTWH(-1920, 100, 1920, 1080),
      );
    });

    test('macOS converts to points and flips y', () {
      // Built-in 2x at Cocoa origin (0,0), 1512x982 pt.
      final builtIn = displayLayoutRect(
        _d('b', 0, 0, 3024, 1964, scale: 2),
        platform: TargetPlatform.macOS,
      );
      // External 1x directly above it (Cocoa y = 982 pt).
      final above = displayLayoutRect(
        _d('e', 0, 982, 2560, 1440),
        platform: TargetPlatform.macOS,
      );
      expect(builtIn, const Rect.fromLTWH(0, -982, 1512, 982));
      expect(above, const Rect.fromLTWH(0, -2422, 2560, 1440));
      expect(above.bottom, builtIn.top);
    });
  });

  testWidgets('tiles are arranged by layout and tap toggles selection', (
    tester,
  ) async {
    final changes = <(String, bool)>[];
    final rows = [
      DisplayRowState(info: _d('left', 0, 0, 1920, 1080), enabled: true),
      DisplayRowState(
        info: _d('right', 1920, 0, 1920, 1080, kind: DisplayKind.virtual),
      ),
      DisplayRowState(
        info: _d(
          'denied',
          3840,
          0,
          1920,
          1080,
          status: CaptureStatus.permissionDenied,
        ),
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 400,
            child: DisplayLayoutView(
              rows: rows,
              platform: TargetPlatform.windows,
              onChanged: (id, on) => changes.add((id, on)),
            ),
          ),
        ),
      ),
    );

    final left = tester.getRect(find.byKey(const ValueKey('left')));
    final right = tester.getRect(find.byKey(const ValueKey('right')));
    expect(left.right, lessThan(right.left));
    expect(left.top, closeTo(right.top, 0.01));
    expect(find.text('Display left'), findsOneWidget);
    expect(find.text('Virtual'), findsOneWidget);
    expect(
      find.text('1920×1080  •  60 Hz', findRichText: true),
      findsNWidgets(3),
    );
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
    final leftTile = tester.widget<Material>(
      find
          .descendant(
            of: find.byKey(const ValueKey('left')),
            matching: find.byType(Material),
          )
          .first,
    );
    final rightTile = tester.widget<Material>(
      find
          .descendant(
            of: find.byKey(const ValueKey('right')),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(leftTile.color, Colors.green.shade100);
    expect(rightTile.color, isNot(Colors.green.shade100));

    await tester.tap(find.byKey(const ValueKey('left')));
    await tester.tap(find.byKey(const ValueKey('right')));
    await tester.tap(find.byKey(const ValueKey('denied')));
    expect(changes, [('left', false), ('right', true)]);
  });
}
