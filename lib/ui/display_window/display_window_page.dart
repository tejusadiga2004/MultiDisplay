import 'package:display_capture_api/display_capture_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../services/window_service.dart';
import 'display_window_state.dart';
import 'name_resolution_label.dart';
import 'use_display_window_view_model.dart';
import 'window_chrome.dart';

class DisplayWindowPage extends HookWidget {
  const DisplayWindowPage({
    super.key,
    required this.spec,
    required this.nativeHandle,
  });

  final DisplayWindowSpec spec;
  final int nativeHandle;

  @override
  Widget build(BuildContext context) {
    final vm = useDisplayWindowViewModel(spec, nativeHandle);
    final s = vm.state;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Children keep fixed positions (placeholders instead of `if`) so
          // that elements are not remounted when the state changes.
          // R-3 / D-2: the whole display, aspect preserved, fitted in the window.
          if (s.textureId != null && s.status == DisplayWindowStatus.running)
            FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: s.widthPx.toDouble(),
                height: s.heightPx.toDouble(),
                child: Texture(
                  textureId: s.textureId!,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            )
          else
            const SizedBox.shrink(),
          // Transparent title strip: the native title bar behaviour lives here.
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: kTitleStripHeight,
            child: IgnorePointer(child: SizedBox.expand()),
          ),
          if (spec.managesWindow)
            WindowsCloseButtonVisual(nativeHandle: nativeHandle),
          if (s.status == DisplayWindowStatus.starting)
            const Center(child: CircularProgressIndicator())
          else
            const SizedBox.shrink(),
          if (s.status == DisplayWindowStatus.failed)
            _FailedOverlay(error: s.error, onRetry: vm.actions.retry)
          else
            const SizedBox.shrink(),
          NameResolutionLabel(text: s.label, semanticsLabel: _semantics(s)),
        ],
      ),
    );
  }

  static String _semantics(DisplayWindowState s) =>
      'Display ${s.name}, ${s.widthPx} by ${s.heightPx}';
}

class _FailedOverlay extends StatelessWidget {
  const _FailedOverlay({required this.error, required this.onRetry});

  final CaptureError? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white70, size: 40),
            const SizedBox(height: 12),
            Text(
              error?.message ?? 'Capture failed',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
