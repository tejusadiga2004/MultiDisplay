import 'package:display_capture_api/display_capture_api.dart';
import 'package:flutter/foundation.dart';

enum ViewStatus { loading, ready, error }

@immutable
class DisplayRowState {
  const DisplayRowState({
    required this.info,
    this.enabled = false,
    this.busy = false,
  });

  final DisplayInfo info;
  final bool enabled;
  final bool busy;

  DisplayRowState copyWith({DisplayInfo? info, bool? enabled, bool? busy}) =>
      DisplayRowState(
        info: info ?? this.info,
        enabled: enabled ?? this.enabled,
        busy: busy ?? this.busy,
      );

  @override
  bool operator ==(Object other) =>
      other is DisplayRowState &&
      other.info == info &&
      other.enabled == enabled &&
      other.busy == busy;

  @override
  int get hashCode => Object.hash(info, enabled, busy);
}

@immutable
class DisplayControllerState {
  const DisplayControllerState({
    this.status = ViewStatus.loading,
    this.rows = const [],
    this.permission = PermissionState.granted,
    this.errorMessage,
  });

  final ViewStatus status;
  final List<DisplayRowState> rows;
  final PermissionState permission;
  final String? errorMessage;

  DisplayControllerState copyWith({
    ViewStatus? status,
    List<DisplayRowState>? rows,
    PermissionState? permission,
    String? errorMessage,
    bool clearError = false,
  }) =>
      DisplayControllerState(
        status: status ?? this.status,
        rows: rows ?? this.rows,
        permission: permission ?? this.permission,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );

  @override
  bool operator ==(Object other) =>
      other is DisplayControllerState &&
      other.status == status &&
      listEquals(other.rows, rows) &&
      other.permission == permission &&
      other.errorMessage == errorMessage;

  @override
  int get hashCode =>
      Object.hash(status, Object.hashAll(rows), permission, errorMessage);
}

/// One-shot side effects the page turns into SnackBars (SPEC §9.0).
sealed class UiEffect {
  const UiEffect();
}

class ShowSnackBar extends UiEffect {
  const ShowSnackBar(this.message);
  final String message;
}
