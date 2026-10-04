import 'package:display_capture_api/display_capture_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'display_controller_state.dart';

String formatResolution(DisplayInfo d) => '${d.widthPx}×${d.heightPx}';

/// "3840×2160 · 60 Hz" (SPEC §9.2). Kind and primary status are shown as
/// [DisplayKindLabel] / [PrimaryDisplayLabel] badges instead of subtitle text.
String formatDisplaySubtitle(DisplayInfo d) {
  final parts = <String>[formatResolution(d)];
  if (d.refreshRateHz > 0) parts.add('${d.refreshRateHz.round()} Hz');
  return parts.join(' · ');
}

const Color kPrimaryLabelColor = Colors.teal;

/// Text + colour for each [DisplayKind]; `null` for [DisplayKind.unknown].
({String text, Color color})? displayKindLabel(DisplayKind kind) =>
    switch (kind) {
      DisplayKind.builtIn => (text: 'Built-in', color: Colors.blue),
      DisplayKind.physical => (text: 'External', color: Colors.orange.shade800),
      DisplayKind.virtual => (text: 'Virtual', color: Colors.deepPurple),
      DisplayKind.unknown => null,
    };

IconData displayKindIcon(DisplayKind kind) => switch (kind) {
  DisplayKind.builtIn => Icons.laptop,
  DisplayKind.virtual => Icons.cast,
  _ => Icons.monitor,
};

class DisplayKindLabel extends StatelessWidget {
  const DisplayKindLabel({super.key, required this.kind, this.filled = false});

  final DisplayKind kind;

  /// Solid kind colour with white text, for use on coloured backgrounds
  /// (e.g. a selected layout tile) where the tinted style would blend in.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final label = displayKindLabel(kind);
    if (label == null) return const SizedBox.shrink();
    return _Badge(text: label.text, color: label.color, filled: filled);
  }
}

class PrimaryDisplayLabel extends StatelessWidget {
  const PrimaryDisplayLabel({super.key, this.filled = false});

  final bool filled;

  @override
  Widget build(BuildContext context) =>
      _Badge(text: 'Primary', color: kPrimaryLabelColor, filled: filled);
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color, required this.filled});

  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final label = (text: text, color: color);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final solid = Color.lerp(label.color, Colors.black, 0.2)!;
    final fg = filled
        ? Colors.white
        : Color.lerp(label.color, dark ? Colors.white : Colors.black, 0.25)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: filled
            ? solid
            : label.color.withValues(alpha: dark ? 0.25 : 0.12),
        border: filled
            ? Border.all(color: Colors.white, width: 1.5)
            : Border.all(color: label.color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label.text,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

const double kDisplayRowHeight = 60;

class DisplayRow extends HookWidget {
  const DisplayRow({super.key, required this.row, required this.onChanged});

  final DisplayRowState row;
  final void Function(bool enabled) onChanged;

  @override
  Widget build(BuildContext context) {
    final info = row.info;
    final scheme = Theme.of(context).colorScheme;
    final canToggle = info.isCapturable && !row.busy;

    return Semantics(
      label: [
        info.name,
        ?displayKindLabel(info.kind)?.text,
        if (info.isPrimary) 'Primary',
        '${info.widthPx} by ${info.heightPx}',
      ].join(', '),
      toggled: row.enabled,
      child: SizedBox(
        height: kDisplayRowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(
                displayKindIcon(info.kind),
                size: 30,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      formatDisplaySubtitle(info),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    // if (!info.isCapturable && info.captureStatusDetail != null)
                    //   Text(
                    //     info.captureStatusDetail!,
                    //     maxLines: 1,
                    //     overflow: TextOverflow.ellipsis,
                    //     style: Theme.of(context).textTheme.bodySmall
                    //         ?.copyWith(color: scheme.error),
                    //   ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (info.isPrimary) ...[
                const PrimaryDisplayLabel(),
                const SizedBox(width: 6),
              ],
              DisplayKindLabel(kind: info.kind),
              const SizedBox(width: 40),
              if (row.busy)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              Transform.scale(
                scale: 0.85,
                transformHitTests: false,
                child: Switch(
                  value: row.enabled,
                  onChanged: canToggle ? onChanged : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
