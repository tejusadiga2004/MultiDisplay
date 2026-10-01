import 'dart:math' as math;

import 'package:display_capture_api/display_capture_api.dart';

/// Placement computed for a new DisplayWindow (SPEC D-3 / §9.3).
class InitialPlacement {
  const InitialPlacement({
    required this.frame,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.targetDisplayId,
  });

  /// Position + nominal size, physical px, virtual-desktop coordinates.
  final WindowFrame frame;
  final double logicalWidth;
  final double logicalHeight;
  final String targetDisplayId;
}

const double kMinLogicalWidth = 320;
const double kMinLogicalHeight = 180;
const int kCascadeStepPx = 32;
const int kCascadeWrap = 8;

/// Picks the first display (in [displays] order) that is not [source], else
/// [source] itself.
DisplayInfo pickTargetDisplay(DisplayInfo source, List<DisplayInfo> displays) {
  for (final d in displays) {
    if (d.id != source.id) return d;
  }
  return source;
}

/// [openOnTarget] = number of DisplayWindows already open on the target.
InitialPlacement computeInitialPlacement({
  required DisplayInfo source,
  required List<DisplayInfo> displays,
  required int openOnTarget,
}) {
  final target = pickTargetDisplay(source, displays);
  final scale = target.scaleFactor > 0 ? target.scaleFactor : 1.0;

  final hasWork = target.workWidth > 0 && target.workHeight > 0;
  final workX = hasWork ? target.workX : target.originX;
  final workY = hasWork ? target.workY : target.originY;
  final workW = hasWork ? target.workWidth : target.widthPx;
  final workH = hasWork ? target.workHeight : target.heightPx;

  // Fit the source aspect ratio inside 50% of the work area, never upscale
  // beyond native size.
  final fit = math.min(
      math.min(workW * 0.5 / source.widthPx, workH * 0.5 / source.heightPx), 1.0);
  var w = (source.widthPx * fit).floorToDouble();
  var h = (source.heightPx * fit).floorToDouble();

  // Minimum size is expressed in logical px.
  final minW = kMinLogicalWidth * scale;
  final minH = kMinLogicalHeight * scale;
  if (w < minW || h < minH) {
    final up = math.max(minW / w, minH / h);
    w = (w * up).ceilToDouble();
    h = (h * up).ceilToDouble();
  }

  final step = (openOnTarget % kCascadeWrap) * kCascadeStepPx * scale;
  final x = workX + ((workW - w) / 2).floor() + step.round();
  final y = workY + ((workH - h) / 2).floor() + step.round();

  return InitialPlacement(
    frame: WindowFrame(x, y, w.round(), h.round()),
    logicalWidth: w / scale,
    logicalHeight: h / scale,
    targetDisplayId: target.id,
  );
}
