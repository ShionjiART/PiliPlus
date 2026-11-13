import 'package:collection/collection.dart';

/// Sends navigation state to the native side once per frame, after every
/// route change and page registration for that frame has finished, so UIKit
/// never sees a short-lived empty state between two pages. Values equal to
/// the last ones sent are skipped.
class NativeNavigationBatch {
  NativeNavigationBatch({required this.schedule, required this.onChanged});

  final void Function(void Function()) schedule;
  final void Function(Map<String, Object> changes) onChanged;
  final _latest = <String, Object>{};
  final _sent = <String, Object>{};
  bool _scheduled = false;
  static const _equality = DeepCollectionEquality();

  void submit(String key, Map<String, Object> value) {
    _latest[key] = value;
    if (_scheduled) return;
    _scheduled = true;
    schedule(() {
      _scheduled = false;
      final changes = <String, Object>{};
      for (final entry in _latest.entries) {
        if (!_equality.equals(_sent[entry.key], entry.value)) {
          changes[entry.key] = entry.value;
          _sent[entry.key] = entry.value;
        }
      }
      if (changes.isNotEmpty) onChanged(changes);
    });
  }
}
