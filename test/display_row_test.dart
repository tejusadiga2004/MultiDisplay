import 'package:display_capture_api/display_capture_api.dart';
import 'package:display_controller/ui/controller/display_controller_state.dart';
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
  test('subtitle no longer embeds the kind', () {
    expect(
      formatDisplaySubtitle(_display(DisplayKind.virtual)),
      '1920×1080 · 60 Hz · Primary',
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

  test('DisplayKind round-trips through the platform map', () {
    for (final kind in DisplayKind.values) {
      expect(DisplayInfo.fromMap(_display(kind).toMap()).kind, kind);
    }
  });
}
