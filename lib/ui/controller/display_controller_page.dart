import 'package:display_capture_api/display_capture_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../services/app_services.dart';
import 'display_controller_state.dart';
import 'display_row.dart';
import 'use_display_controller_view_model.dart';

class DisplayControllerPage extends HookWidget {
  const DisplayControllerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = useDisplayControllerViewModel();
    final state = vm.state;
    final permissionBannerDismissed = useState(false);

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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/icon/app_icon.png',
                        width: 48,
                        height: 48,
                        filterQuality: FilterQuality.medium,
                        semanticLabel: 'Display Controller icon',
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Display Controller',
                              style: textTheme.headlineSmall,
                            ),
                            Text(
                              subtitle,
                              style: textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (state.permission != PermissionState.granted &&
                    !permissionBannerDismissed.value)
                  MaterialBanner(
                    content: const Text(
                      'Screen Recording permission is required to show displays. After granting access, relaunch Display Controller.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: vm.actions.requestPermission,
                        child: const Text('Grant Access'),
                      ),
                      TextButton(
                        onPressed: vm.actions.openPermissionSettings,
                        child: const Text('Open Settings'),
                      ),
                      TextButton(
                        onPressed: () => permissionBannerDismissed.value = true,
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),
                Expanded(child: _body(context, vm)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, DisplayControllerViewModel vm) {
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
        return ListView.builder(
          itemCount: state.rows.length,
          itemBuilder: (context, i) {
            final row = state.rows[i];
            return DisplayRow(
              key: ValueKey(row.info.id),
              row: row,
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
