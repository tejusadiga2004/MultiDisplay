import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/display_layout.dart';
export '../../services/display_layout.dart' show displayLayoutRect;
import 'display_controller_state.dart';
import 'display_row.dart';

/// Displays drawn as rectangles in their OS arrangement. Tapping a rectangle
/// toggles that display, exactly like the switch in the list view.
class DisplayLayoutView extends StatelessWidget {
  const DisplayLayoutView({
    super.key,
    required this.rows,
    required this.onChanged,
    this.platform,
  });

  final List<DisplayRowState> rows;
  final void Function(String id, bool enabled) onChanged;
  final TargetPlatform? platform;

  static const double _padding = 24;
  static const double _gap = 6;

  @override
  Widget build(BuildContext context) {
    final rects = [
      for (final r in rows) displayLayoutRect(r.info, platform: platform),
    ];
    final bounds = rects.reduce((a, b) => a.expandToInclude(b));

    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = math.max(1.0, constraints.maxWidth - _padding * 2);
        final availH = math.max(1.0, constraints.maxHeight - _padding * 2);
        final scale = math.min(
          availW / math.max(1.0, bounds.width),
          availH / math.max(1.0, bounds.height),
        );
        final dx = _padding + (availW - bounds.width * scale) / 2;
        final dy = _padding + (availH - bounds.height * scale) / 2;

        return Stack(
          children: [
            for (var i = 0; i < rows.length; i++)
              Positioned(
                key: ValueKey(rows[i].info.id),
                left: dx + (rects[i].left - bounds.left) * scale + _gap / 2,
                top: dy + (rects[i].top - bounds.top) * scale + _gap / 2,
                width: math.max(0.0, rects[i].width * scale - _gap),
                height: math.max(0.0, rects[i].height * scale - _gap),
                child: DisplayTile(
                  row: rows[i],
                  onChanged: (on) => onChanged(rows[i].info.id, on),
                ),
              ),
          ],
        );
      },
    );
  }
}

class DisplayTile extends StatelessWidget {
  const DisplayTile({super.key, required this.row, required this.onChanged});

  final DisplayRowState row;
  final void Function(bool enabled) onChanged;

  @override
  Widget build(BuildContext context) {
    final info = row.info;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canToggle = info.isCapturable && !row.busy;
    final selected = row.enabled;

    final dark = theme.brightness == Brightness.dark;
    final selectedBg = dark ? Colors.green.shade800 : Colors.green.shade100;
    final selectedFg = dark ? Colors.white : Colors.green.shade900;

    final fg = selected ? selectedFg : scheme.onSurface;
    final fgMuted = selected ? selectedFg : scheme.onSurfaceVariant;

    return Semantics(
      button: true,
      enabled: canToggle,
      toggled: selected,
      label: [
        info.name,
        ?displayKindLabel(info.kind)?.text,
        '${info.widthPx} by ${info.heightPx}',
      ].join(', '),
      excludeSemantics: true,
      child: Tooltip(
        message: info.name,
        waitDuration: const Duration(milliseconds: 600),
        child: Opacity(
          opacity: info.isCapturable ? 1 : 0.6,
          child: Material(
            color: selected ? selectedBg : scheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: selected ? Colors.green.shade600 : scheme.outlineVariant,
                width: selected ? 2.5 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: canToggle ? () => onChanged(!selected) : null,
              mouseCursor: canToggle
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: LayoutBuilder(
                builder: (context, c) => _content(
                  context,
                  c,
                  fg: fg,
                  fgMuted: fgMuted,
                  checkColor: dark
                      ? Colors.green.shade900
                      : Colors.green.shade700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Fixed-size text (no per-tile scaling, so all tiles read the same);
  /// lower-priority lines are dropped as the tile gets smaller.
  Widget _content(
    BuildContext context,
    BoxConstraints c, {
    required Color fg,
    required Color fgMuted,
    required Color checkColor,
  }) {
    final info = row.info;
    final theme = Theme.of(context);
    final h = c.maxHeight;
    final showHeader = h >= 64 && c.maxWidth >= 90;
    final showIcon = h >= 150;
    final showDetails = h >= 44;
    final showStatus =
        h >= 120 && !info.isCapturable && info.captureStatusDetail != null;

    final detailStyle = theme.textTheme.bodySmall?.copyWith(color: fgMuted);
    final hasHz = info.refreshRateHz > 0;

    final body = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (showIcon) ...[
          Icon(displayKindIcon(info.kind), size: 28, color: fgMuted),
          const SizedBox(height: 6),
        ],
        Text(
          info.name,
          maxLines: h >= 130 ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(
            color: fg,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        if (showDetails) ...[
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: formatResolution(info)),
                if (hasHz) ...[
                  const TextSpan(
                    text: '  •  ',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  TextSpan(text: '${info.refreshRateHz.round()} Hz'),
                ],
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: detailStyle,
          ),
          if (info.isPrimary)
            Text(
              'Primary',
              maxLines: 1,
              style: detailStyle?.copyWith(fontWeight: FontWeight.w600),
            ),
        ],
        if (showStatus) ...[
          const SizedBox(height: 4),
          Text(
            info.captureStatusDetail!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          if (showHeader)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                DisplayKindLabel(kind: info.kind, filled: row.enabled),
                const Spacer(),
                _selectionIndicator(row.enabled, checkColor),
              ],
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, bc) {
                final w = math.max(1.0, bc.maxWidth - 8);
                // Shrink only if the content doesn't fit at normal size.
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: w,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: body.children,
                    ),
                  ),
                );
              },
            ),
          ),
          if (!showHeader && (row.enabled || row.busy))
            Align(
              alignment: Alignment.centerRight,
              child: _selectionIndicator(row.enabled, checkColor),
            ),
        ],
      ),
    );
  }

  /// Spinner while starting, a check mark when selected, otherwise an empty
  /// slot of the same size so the tile content doesn't shift.
  Widget _selectionIndicator(bool selected, Color color) {
    const size = 22.0;
    if (row.busy) {
      return const SizedBox(
        width: size,
        height: size,
        child: Padding(
          padding: EdgeInsets.all(3),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (!selected) return const SizedBox(width: size, height: size);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: const Icon(Icons.check, size: 14, color: Colors.white),
    );
  }
}
