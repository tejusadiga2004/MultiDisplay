/// Domain model shared by every layer (SPEC Â§5, Â§6.1).
library;

enum DisplayKind { physical, virtual, unknown }

enum CaptureStatus { available, permissionDenied, unsupported, protected }

enum PermissionState { granted, denied, notDetermined }

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return fallback;
}

class DisplayInfo {
  const DisplayInfo({
    required this.id,
    required this.name,
    required this.widthPx,
    required this.heightPx,
    this.scaleFactor = 1.0,
    this.refreshRateHz = 0,
    this.originX = 0,
    this.originY = 0,
    this.workX = 0,
    this.workY = 0,
    this.workWidth = 0,
    this.workHeight = 0,
    this.isPrimary = false,
    this.kind = DisplayKind.unknown,
    this.captureStatus = CaptureStatus.available,
    this.captureStatusDetail,
  });

  final String id;
  final String name;
  final int widthPx;
  final int heightPx;
  final double scaleFactor;
  final double refreshRateHz;
  final int originX;
  final int originY;

  /// Work area (excludes taskbar/dock) in physical px, virtual-desktop
  /// coordinates. Zero width/height means unknown: use the full display rect.
  final int workX;
  final int workY;
  final int workWidth;
  final int workHeight;
  final bool isPrimary;
  final DisplayKind kind;
  final CaptureStatus captureStatus;
  final String? captureStatusDetail;

  bool get isCapturable => captureStatus == CaptureStatus.available;

  factory DisplayInfo.fromMap(Map<Object?, Object?> m) => DisplayInfo(
        id: m['id']! as String,
        name: m['name']! as String,
        widthPx: (m['widthPx']! as num).toInt(),
        heightPx: (m['heightPx']! as num).toInt(),
        scaleFactor: (m['scaleFactor'] as num?)?.toDouble() ?? 1.0,
        refreshRateHz: (m['refreshRateHz'] as num?)?.toDouble() ?? 0,
        originX: (m['originX'] as num?)?.toInt() ?? 0,
        originY: (m['originY'] as num?)?.toInt() ?? 0,
        workX: (m['workX'] as num?)?.toInt() ?? 0,
        workY: (m['workY'] as num?)?.toInt() ?? 0,
        workWidth: (m['workWidth'] as num?)?.toInt() ?? 0,
        workHeight: (m['workHeight'] as num?)?.toInt() ?? 0,
        isPrimary: m['isPrimary'] as bool? ?? false,
        kind: _enumByName(DisplayKind.values, m['kind'], DisplayKind.unknown),
        captureStatus: _enumByName(
            CaptureStatus.values, m['captureStatus'], CaptureStatus.available),
        captureStatusDetail: m['captureStatusDetail'] as String?,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'widthPx': widthPx,
        'heightPx': heightPx,
        'scaleFactor': scaleFactor,
        'refreshRateHz': refreshRateHz,
        'originX': originX,
        'originY': originY,
        'workX': workX,
        'workY': workY,
        'workWidth': workWidth,
        'workHeight': workHeight,
        'isPrimary': isPrimary,
        'kind': kind.name,
        'captureStatus': captureStatus.name,
        'captureStatusDetail': captureStatusDetail,
      };

  DisplayInfo copyWith({String? name, int? widthPx, int? heightPx}) => DisplayInfo(
        id: id,
        name: name ?? this.name,
        widthPx: widthPx ?? this.widthPx,
        heightPx: heightPx ?? this.heightPx,
        scaleFactor: scaleFactor,
        refreshRateHz: refreshRateHz,
        originX: originX,
        originY: originY,
        workX: workX,
        workY: workY,
        workWidth: workWidth,
        workHeight: workHeight,
        isPrimary: isPrimary,
        kind: kind,
        captureStatus: captureStatus,
        captureStatusDetail: captureStatusDetail,
      );

  @override
  bool operator ==(Object other) =>
      other is DisplayInfo &&
      other.id == id &&
      other.name == name &&
      other.widthPx == widthPx &&
      other.heightPx == heightPx &&
      other.scaleFactor == scaleFactor &&
      other.refreshRateHz == refreshRateHz &&
      other.originX == originX &&
      other.originY == originY &&
      other.workX == workX &&
      other.workY == workY &&
      other.workWidth == workWidth &&
      other.workHeight == workHeight &&
      other.isPrimary == isPrimary &&
      other.kind == kind &&
      other.captureStatus == captureStatus &&
      other.captureStatusDetail == captureStatusDetail;

  @override
  int get hashCode => Object.hash(id, name, widthPx, heightPx, scaleFactor,
      refreshRateHz, originX, originY, workX, workY, workWidth, workHeight, isPrimary, kind, captureStatus, captureStatusDetail);

  @override
  String toString() => 'DisplayInfo($id, $name, ${widthPx}x$heightPx)';
}

class CaptureOptions {
  const CaptureOptions({
    this.maxWidthPx,
    this.maxHeightPx,
    this.fps,
    this.showCursor = true,
    this.ownerWindowHandle,
  });

  final int? maxWidthPx;
  final int? maxHeightPx;
  final int? fps;
  final bool showCursor;

  /// Native handle (HWND address) of the window that owns the session; the
  /// native layer stops the session when that window is destroyed.
  final int? ownerWindowHandle;
}

class CaptureSession {
  const CaptureSession({
    required this.sessionId,
    required this.textureId,
    required this.widthPx,
    required this.heightPx,
  });

  final int sessionId;
  final int textureId;
  final int widthPx;
  final int heightPx;
}

/// Physical pixels in virtual-desktop coordinates.
class WindowFrame {
  const WindowFrame(this.x, this.y, this.width, this.height);
  final int x;
  final int y;
  final int width;
  final int height;
}

class CloseHoverEvent {
  const CloseHoverEvent({required this.nativeHandle, required this.hot});
  final int nativeHandle;
  final bool hot;
}

class DiagnosticsInfo {
  const DiagnosticsInfo({
    required this.renderPath,
    required this.backend,
    required this.gpuName,
    required this.driver,
  });

  /// "d3d11-shared" | "metal-iosurface" | "vulkan-gl-interop" | "cpu-fallback"
  final String renderPath;
  final String backend;
  final String gpuName;
  final String driver;

  factory DiagnosticsInfo.fromMap(Map<Object?, Object?> m) => DiagnosticsInfo(
        renderPath: m['renderPath'] as String? ?? 'unknown',
        backend: m['backend'] as String? ?? 'unknown',
        gpuName: m['gpuName'] as String? ?? '',
        driver: m['driver'] as String? ?? '',
      );
}

sealed class CaptureEvent {
  const CaptureEvent();
}

class FrameSizeChanged extends CaptureEvent {
  const FrameSizeChanged(this.widthPx, this.heightPx);
  final int widthPx;
  final int heightPx;
}

class CaptureStalled extends CaptureEvent {
  const CaptureStalled();
}

class CaptureResumed extends CaptureEvent {
  const CaptureResumed();
}

class DisplayLost extends CaptureEvent {
  const DisplayLost();
}

class CaptureFailed extends CaptureEvent {
  const CaptureFailed(this.error);
  final CaptureError error;
}

enum CaptureErrorCode {
  displayNotFound,
  permissionDenied,
  unsupported,
  wrongSource,
  gpuError,
  captureFailed,
  internal;

  static CaptureErrorCode fromWire(String? code) => switch (code) {
        'DISPLAY_NOT_FOUND' => displayNotFound,
        'PERMISSION_DENIED' => permissionDenied,
        'UNSUPPORTED' => unsupported,
        'WRONG_SOURCE' => wrongSource,
        'GPU_ERROR' => gpuError,
        'CAPTURE_FAILED' => captureFailed,
        _ => internal,
      };
}

class CaptureError implements Exception {
  const CaptureError(this.code, this.message);
  final CaptureErrorCode code;
  final String message;

  @override
  String toString() => 'CaptureError(${code.name}: $message)';
}

