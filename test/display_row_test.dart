import 'package:display_capture_api/display_capture_api.dart';
import 'package:display_controller/ui/controller/display_controller_state.dart';
import 'package:display_controller/ui/controller/display_layout_view.dart';
import 'package:display_controller/ui/controller/display_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DisplayInfo _display(DisplayKind kind) => DisplayInfo(
  id: 'id-${kind.name}',
  name: 'Display ${kind.name}',
  widthPx: 1920,
  heightPx: 1080,
  refreshRateHz: 60,
  isPrimary: true,
  kind: kind,
);

void main() {
  test('subtitle no longer embeds the kind or primary status', () {
    expect(
      formatDisplaySubtitle(_display(DisplayKind.virtual)),
      '1920×1080 · 60 Hz',
    );
  });

  test('each known kind has a distinct coloured label', () {
    final builtIn = displayKindLabel(DisplayKind.builtIn)!;
    final external = displayKindLabel(DisplayKind.physical)!;
    final virtual = displayKindLabel(DisplayKind.virtual)!;
    expect(
      [builtIn.text, external.text, virtual.text],
      ['Built-in', 'External', 'Virtual'],
    );
    expect({builtIn.color, external.color, virtual.color}, hasLength(3));
    expect(displayKindLabel(DisplayKind.unknown), isNull);
  });

  testWidgets('DisplayRow renders the kind label', (tester) async {
    for (final (kind, text) in [
      (DisplayKind.builtIn, 'Built-in'),
      (DisplayKind.physical, 'External'),
      (DisplayKind.virtual, 'Virtual'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DisplayRow(
              row: DisplayRowState(info: _display(kind)),
              onChanged: (_) {},
            ),
          ),
        ),
      );
      expect(find.text(text), findsOneWidget);
      expect(find.byType(PrimaryDisplayLabel), findsOneWidget);
      expect(find.text('Primary'), findsOneWidget);
      expect(tester.getSize(find.byType(DisplayRow)).height, 60);
      expect(tester.takeException(), isNull);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DisplayRow(
            row: DisplayRowState(info: _display(DisplayKind.unknown)),
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.byType(DisplayKindLabel), findsOneWidget);
    expect(find.text('External'), findsNothing);
  });

  testWidgets('non-primary displays have no Primary label', (tester) async {
    final info = _display(DisplayKind.physical);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DisplayRow(
            row: DisplayRowState(
              info: DisplayInfo.fromMap({...info.toMap(), 'isPrimary': false}),
            ),
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.byType(PrimaryDisplayLabel), findsNothing);
    expect(find.text('Primary'), findsNothing);
  });

  testWidgets('Layout tile shows a Primary label beside the kind label', (
    tester,
  ) async {
    final primary = _display(DisplayKind.builtIn);
    final other = DisplayInfo.fromMap({
      ..._display(DisplayKind.physical).toMap(),
      'isPrimary': false,
      'originX': 1920,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 400,
            child: DisplayLayoutView(
              rows: [
                DisplayRowState(info: primary),
                DisplayRowState(info: other),
              ],
              onChanged: (_, _) {},
            ),
          ),
        ),
      ),
    );
    expect(find.byType(PrimaryDisplayLabel), findsOneWidget);
    expect(find.text('Built-in'), findsOneWidget);
    expect(find.text('External'), findsOneWidget);
    expect(
      tester.getCenter(find.byType(PrimaryDisplayLabel)).dx,
      greaterThan(tester.getCenter(find.text('Built-in')).dx),
    );
    expect(tester.takeException(), isNull);
  });

  test('DisplayKind round-trips through the platform map', () {
    for (final kind in DisplayKind.values) {
      expect(DisplayInfo.fromMap(_display(kind).toMap()).kind, kind);
    }
  });
}
