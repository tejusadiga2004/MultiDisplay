import 'dart:math' as math;

import 'package:display_capture_api/display_capture_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../services/app_services.dart';
import '../../services/display_layout.dart';
import '../../services/window_service.dart';
import 'display_window_page.dart';
import 'window_chrome.dart';

class CompositeWindowPage extends HookWidget {
  const CompositeWindowPage({
    super.key,
    required this.spec,
    required this.nativeHandle,
  });

  final CompositeWindowSpec spec;
  final int nativeHandle;

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final displays = useValueListenable(spec.displays);
    Future<void> initialize() async {
      try {
        await services.api.setupDisplayWindow(
          nativeHandle: nativeHandle,
          initialFrame: spec.initialFrame,
          allowFullScreen: true,
        );
        if (spec.active) {
          services.windows.report(const WindowReady(compositeWindowId));
        }
      } on Object catch (error) {
        final failure = error is CaptureError
            ? error
            : CaptureError(CaptureErrorCode.internal, '$error');
        if (spec.active) {
          services.windows.report(WindowFailed(compositeWindowId, failure));
        }
        rethrow;
      }
    }

    final setup = useMemoized(initialize, [spec, nativeHandle]);
    final ready = useFuture(setup);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (ready.hasError)
            Center(
              child: Text(
                '${ready.error}',
                style: const TextStyle(color: Colors.white),
              ),
            )
          else if (ready.connectionState != ConnectionState.done)
            const Center(child: CircularProgressIndicator())
          else
            CompositeCanvas(
              displays: displays,
              tileBuilder: (display) => _CaptureTile(
                key: ValueKey(display.id),
                display: display,
                parent: spec,
                nativeHandle: nativeHandle,
              ),
            ),
          WindowsCloseButtonVisual(nativeHandle: nativeHandle),
        ],
      ),
    );
  }
}

class CompositeCanvas extends StatelessWidget {
  const CompositeCanvas({
    super.key,
    required this.displays,
    required this.tileBuilder,
    this.platform,
  });
  final List<DisplayInfo> displays;
  final Widget Function(DisplayInfo) tileBuilder;
  final TargetPlatform? platform;

  @override
  Widget build(BuildContext context) {
    if (displays.isEmpty) return const SizedBox.shrink();
    final rects = [
      for (final d in displays) displayLayoutRect(d, platform: platform),
    ];
    final bounds = rects.reduce((a, b) => a.expandToInclude(b));
    if (bounds.width <= 0 || bounds.height <= 0) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.min(
          constraints.maxWidth / bounds.width,
          constraints.maxHeight / bounds.height,
        );
        final dx = (constraints.maxWidth - bounds.width * scale) / 2;
        final dy = (constraints.maxHeight - bounds.height * scale) / 2;
        return Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < displays.length; i++)
              Positioned(
                key: ValueKey(displays[i].id),
                left: dx + (rects[i].left - bounds.left) * scale,
                top: dy + (rects[i].top - bounds.top) * scale,
                width: rects[i].width * scale,
                height: rects[i].height * scale,
                child: tileBuilder(displays[i]),
              ),
          ],
        );
      },
    );
  }
}

class _CaptureTile extends HookWidget {
  const _CaptureTile({
    super.key,
    required this.display,
    required this.parent,
    required this.nativeHandle,
  });
  final DisplayInfo display;
  final CompositeWindowSpec parent;
  final int nativeHandle;

  @override
  Widget build(BuildContext context) {
    final spec = useMemoized(
      () => EmbeddedDisplaySpec(
        display: display,
        initialFrame: parent.initialFrame,
        logicalSize: parent.logicalSize,
      ),
      [display.id, parent],
    );
    useEffect(() {
      spec.info.value = display;
      return null;
    }, [display]);
    return DisplayWindowPage(spec: spec, nativeHandle: nativeHandle);
  }
}
