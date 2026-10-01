import 'package:display_capture_api/display_capture_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'display_controller_state.dart';

String formatResolution(DisplayInfo d) => '${d.widthPx}×${d.heightPx}';

/// "3840×2160 · 60 Hz · Primary · Virtual" (SPEC §9.2).
String formatDisplaySubtitle(DisplayInfo d) {
  final parts = <String>[formatResolution(d)];
  if (d.refreshRateHz > 0) parts.add('${d.refreshRateHz.round()} Hz');
  if (d.isPrimary) parts.add('Primary');
  if (d.kind == DisplayKind.virtual) parts.add('Virtual');
  return parts.join(' · ');
}

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
      label: '${info.name}, ${info.widthPx} by ${info.heightPx}',
      toggled: row.enabled,
      child: SizedBox(
        height: 72,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(info.kind == DisplayKind.virtual ? Icons.cast : Icons.monitor,
                  color: scheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(info.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge),
                    Text(formatDisplaySubtitle(info),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                    if (!info.isCapturable && info.captureStatusDetail != null)
                      Text(info.captureStatusDetail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.error)),
                  ],
                ),
              ),
              if (row.busy)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              Switch(
                value: row.enabled,
                onChanged: canToggle ? onChanged : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
