import 'package:display_capture_api/display_capture_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Convert the native desktop coordinates to a shared, y-down canvas.
/// macOS reports per-display scaled Cocoa origins, so undo that scale first.
Rect displayLayoutRect(DisplayInfo d, {TargetPlatform? platform}) {
  if ((platform ?? defaultTargetPlatform) == TargetPlatform.macOS) {
    final scale = d.scaleFactor > 0 ? d.scaleFactor : 1.0;
    return Rect.fromLTWH(
      d.originX / scale,
      -(d.originY + d.heightPx) / scale,
      d.widthPx / scale,
      d.heightPx / scale,
    );
  }
  return Rect.fromLTWH(
    d.originX.toDouble(),
    d.originY.toDouble(),
    d.widthPx.toDouble(),
    d.heightPx.toDouble(),
  );
}
