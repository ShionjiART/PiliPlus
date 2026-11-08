import 'package:flutter/services.dart' show DeviceOrientation;

/// Cancels obsolete display requests before touching Flutter's stored mask.
/// Completion is sent only for the newest request; native validates it again
/// after Flutter's queued UIKit update before settling/releasing scene geometry.
class FoldOrientationRequests {
  FoldOrientationRequests({
    required this.validate,
    required this.apply,
    required this.complete,
  });

  final Future<bool> Function(int id) validate;
  final Future<void> Function(List<DeviceOrientation>) apply;
  final Future<void> Function(int id, bool success) complete;
  int _latest = -1;

  Future<void> handle(Map<Object?, Object?> request) async {
    final id = request['id'] as int;
    if (id <= _latest) return;
    _latest = id;
    if (!await validate(id) || id != _latest) return;
    final orientations = (request['orientations'] as List)
        .map((value) => DeviceOrientation.values.byName(value as String))
        .toList();
    try {
      await apply(orientations);
    } catch (_) {
      if (id == _latest) await complete(id, false);
      return;
    }
    if (id == _latest) await complete(id, true);
  }
}
