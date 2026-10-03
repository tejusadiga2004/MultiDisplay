import 'package:display_capture_api/display_capture_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../services/app_services.dart';
import 'display_controller_state.dart';
import 'display_layout_view.dart';
import 'display_row.dart';
import 'use_display_controller_view_model.dart';

enum DisplayViewMode { list, layout }

class DisplayControllerPage extends HookWidget {
  const DisplayControllerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = useDisplayControllerViewModel();
    final state = vm.state;
    final permissionBannerDismissed = useState(false);
    final viewMode = useState(DisplayViewMode.list);

    // One-shot effects -> SnackBars.
    final effects = useStream(vm.actions.effects);
    useEffect(() {
      final effect = effects.data;
      if (effect is ShowSnackBar) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(effect.message)));
      }
      return null;
    }, [effects.data]);

    final textTheme = Theme.of(context).textTheme;
    final n = state.rows.length;
    final subtitle = switch (n) {
      0 => 'No displays',
      1 => '1 display',
      _ => '$n displays',
    };

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.keyD,
          control: true,
          shift: true,
        ): () =>
            _showDiagnostics(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state.permission != PermissionState.granted &&
                    !permissionBannerDismissed.value)
                  _PermissionBanner(
                    onGrant: vm.actions.requestPermission,
                    onOpenSettings: vm.actions.openPermissionSettings,
                    onDismiss: () => permissionBannerDismissed.value = true,
                  ),
                // Padding(
                //   padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                //   child: Row(
                //     children: [
                //       Image.asset(
                //         'assets/icon/app_icon.png',
                //         width: 32,
                //         height: 32,
                //         filterQuality: FilterQuality.medium,
                //         semanticLabel: 'Display Controller icon',
                //       ),
                //       const SizedBox(width: 12),
                //       Expanded(
                //         child: Text(
                //           'Display Controller',
                //           style: textTheme.titleMedium,
                //         ),
                //       ),
                //     ],
                //   ),
                // ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SegmentedButton<DisplayWindowMode>(
                          key: const ValueKey('windowModeToggle'),
                          style: _compactButtonStyle(context),
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: DisplayWindowMode.separate,
                              tooltip: 'Separate windows',
                              icon: Icon(Icons.filter_none),
                            ),
                            ButtonSegment(
                              value: DisplayWindowMode.composite,
                              tooltip: 'Single layout',
                              icon: Icon(Icons.dashboard),
                            ),
                          ],
                          selected: {state.windowMode},
                          onSelectionChanged:
                              state.switchingMode ||
                                  state.rows.any((r) => r.busy)
                              ? null
                              : (selection) =>
                                    vm.actions.setWindowMode(selection.first),
                        ),
                        SegmentedButton<DisplayViewMode>(
                          style: _compactButtonStyle(context),
                          key: const ValueKey('viewModeToggle'),
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: DisplayViewMode.list,
                              icon: Icon(Icons.view_list),
                              label: Text('List'),
                              tooltip: 'Display list',
                            ),
                            ButtonSegment(
                              value: DisplayViewMode.layout,
                              icon: Icon(Icons.dashboard_outlined),
                              label: Text('Layout'),
                              tooltip: 'Display layout',
                            ),
                          ],
                          selected: {viewMode.value},
                          onSelectionChanged: (s) => viewMode.value = s.first,
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                Expanded(child: _body(context, vm, viewMode.value)),
                _Footer(text: subtitle),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ButtonStyle _compactButtonStyle(BuildContext context) => ButtonStyle(
    visualDensity: VisualDensity.compact,
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
    iconSize: const WidgetStatePropertyAll(18),
    textStyle: WidgetStatePropertyAll(Theme.of(context).textTheme.labelSmall),
  );

  Widget _body(
    BuildContext context,
    DisplayControllerViewModel vm,
    DisplayViewMode mode,
  ) {
    final state = vm.state;
    switch (state.status) {
      case ViewStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case ViewStatus.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(
                "Couldn't read displays",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (state.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(state.errorMessage!, textAlign: TextAlign.center),
                ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: vm.actions.retry,
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      case ViewStatus.ready:
        if (state.rows.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.monitor, size: 48),
                SizedBox(height: 12),
                Text('No displays found'),
              ],
            ),
          );
        }
        if (mode == DisplayViewMode.layout) {
          return DisplayLayoutView(
            rows: [
              for (final row in state.rows)
                row.copyWith(busy: row.busy || state.switchingMode),
            ],
            onChanged: vm.actions.setEnabled,
          );
        }
        return ListView.separated(
          itemCount: state.rows.length,
          separatorBuilder: (context, _) =>
              const Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
          itemBuilder: (context, i) {
            final row = state.rows[i];
            return DisplayRow(
              key: ValueKey(row.info.id),
              row: row.copyWith(busy: row.busy || state.switchingMode),
              onChanged: (on) => vm.actions.setEnabled(row.info.id, on),
            );
          },
        );
    }
  }

  Future<void> _showDiagnostics(BuildContext context) async {
    final api = AppServices.of(context).api;
    final d = await api.diagnostics();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Diagnostics'),
        content: SelectableText(
          'Render path: ${d.renderPath}\n'
          'Backend: ${d.backend}\nGPU: ${d.gpuName}\nDriver: ${d.driver}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({
    required this.onGrant,
    required this.onOpenSettings,
    required this.onDismiss,
  });

  final VoidCallback onGrant;
  final VoidCallback onOpenSettings;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const buttonStyle = ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
    );
    return Container(
      key: const ValueKey('permissionBanner'),
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Screen Recording permission required. Relaunch after granting access.',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(
            style: buttonStyle,
            onPressed: onGrant,
            child: const Text('Grant Access', style: TextStyle(fontSize: 12)),
          ),
          TextButton(
            style: buttonStyle,
            onPressed: onOpenSettings,
            child: const Text('Open Settings', style: TextStyle(fontSize: 12)),
          ),
          IconButton(
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            onPressed: onDismiss,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('controllerFooter'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1, thickness: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
