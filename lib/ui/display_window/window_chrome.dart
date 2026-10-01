import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../services/app_services.dart';

/// Height of the transparent title strip (SPEC §9.4).
const double kTitleStripHeight = 32;
const double kCloseButtonWidth = 46;

/// Windows only: Flutter draws the *visual* of the close button; clicks are
/// handled natively through the HTCLOSE hit-test (SPEC §9.5). Renders nothing
/// on other platforms, where the native button is used.
class WindowsCloseButtonVisual extends HookWidget {
  const WindowsCloseButtonVisual({super.key, required this.nativeHandle});

  final int nativeHandle;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) return const SizedBox.shrink();
    final api = AppServices.of(context).api;
    final hot = useState(false);
    useEffect(() {
      final sub = api.closeHoverEvents
          .where((e) => e.nativeHandle == nativeHandle)
          .listen((e) {
        debugPrint('DBG hover ${e.hot} for $nativeHandle');
        hot.value = e.hot;
      });
      debugPrint('DBG subscribed chrome hover for $nativeHandle');
      return sub.cancel;
    }, [api, nativeHandle]);

    return Positioned(
      top: 0,
      right: 0,
      width: kCloseButtonWidth,
      height: kTitleStripHeight,
      child: IgnorePointer(
        child: ColoredBox(
          color: hot.value ? const Color(0xFFC42B1C) : Colors.transparent,
          child: Center(
            child: Icon(Icons.close,
                size: 14,
                // On a transparent title bar over arbitrary video, keep the glyph
                // legible with a soft shadow.
                color: Colors.white,
                shadows: hot.value
                    ? null
                    : const [Shadow(blurRadius: 3, color: Color(0xAA000000))]),
          ),
        ),
      ),
    );
  }
}
