import 'package:display_capture_api/display_capture_api.dart';
import 'package:flutter/foundation.dart';

enum DisplayWindowStatus { starting, running, failed, closed }

@immutable
class DisplayWindowState {
  const DisplayWindowState({
    required this.name,
    required this.widthPx,
    required this.heightPx,
    this.status = DisplayWindowStatus.starting,
    this.textureId,
    this.error,
  });

  final String name;
  final int widthPx;
  final int heightPx;
  final DisplayWindowStatus status;
  final int? textureId;
  final CaptureError? error;

  /// Text of the bottom-right label (R-6, D-5): "Name · 3840×2160".
  String get label => '$name · $widthPx×$heightPx';

  DisplayWindowState copyWith({
    String? name,
    int? widthPx,
    int? heightPx,
    DisplayWindowStatus? status,
    int? textureId,
    CaptureError? error,
    bool clearError = false,
  }) =>
      DisplayWindowState(
        name: name ?? this.name,
        widthPx: widthPx ?? this.widthPx,
        heightPx: heightPx ?? this.heightPx,
        status: status ?? this.status,
        textureId: textureId ?? this.textureId,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  bool operator ==(Object other) =>
      other is DisplayWindowState &&
      other.name == name &&
      other.widthPx == widthPx &&
      other.heightPx == heightPx &&
      other.status == status &&
      other.textureId == textureId &&
      other.error == error;

  @override
  int get hashCode => Object.hash(name, widthPx, heightPx, status, textureId, error);
}
