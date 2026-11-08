import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';
import 'package:PiliPlus/utils/ios/fold_orientation_sync.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native fold geometry cannot suppress the next explicit player direction', () async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      invalidatePreferredOrientationCache();
    });
    invalidatePreferredOrientationCache();
    await portraitUpMode();
    await portraitUpMode();
    expect(calls.length, 1);
    // The hinge coordinator changes scene preferences to all orientations.
    // A vertical/fullscreen request must still reach Flutter's platform plugin.
    invalidatePreferredOrientationCache();
    await portraitUpMode();
    expect(calls.length, 2);
    expect(calls.last.method, 'SystemChrome.setPreferredOrientations');
    expect(calls.last.arguments, ['DeviceOrientation.portraitUp']);
  });

  test(
    'native request releases an old fullscreen mask and acknowledges it',
    () async {
      final events = <Object>[];
      final handler = FoldOrientationRequests(
        validate: (id) async => true,
        apply: (directions) async => events.add(directions),
        complete: (id, success) async => events.add((id, success)),
      );
      await handler.handle({
        'id': 1,
        'orientations': ['landscapeLeft'],
      });
      await handler.handle({'id': 2, 'orientations': <String>[]});
      expect(events, [
        [DeviceOrientation.landscapeLeft],
        (1, true),
        <DeviceOrientation>[],
        (2, true),
      ]);
    },
  );

  test(
    'a cancelled old-display request never writes Flutter orientation',
    () async {
      final applied = <Object>[];
      final handler = FoldOrientationRequests(
        validate: (_) async => false,
        apply: (directions) async => applied.add(directions),
        complete: (id, success) async => applied.add((id, success)),
      );
      await handler.handle({
        'id': 1,
        'orientations': ['landscapeRight'],
      });
      expect(applied, isEmpty);
    },
  );

  test(
    'newer display request wins while an old acknowledgement is waiting',
    () async {
      final oldApply = Completer<void>();
      final oldStarted = Completer<void>();
      final acknowledgements = <Object>[];
      final handler = FoldOrientationRequests(
        validate: (_) async => true,
        apply: (directions) async {
          if (directions.contains(DeviceOrientation.landscapeRight)) {
            oldStarted.complete();
            await oldApply.future;
          }
        },
        complete: (id, success) async => acknowledgements.add((id, success)),
      );
      final old = handler.handle({
        'id': 1,
        'orientations': ['landscapeRight'],
      });
      await oldStarted.future;
      await handler.handle({
        'id': 2,
        'orientations': ['landscapeLeft'],
      });
      oldApply.complete();
      await old;
      await handler.handle({
        'id': 1,
        'orientations': ['landscapeRight'],
      });
      expect(acknowledgements, [(2, true)]);
    },
  );

  test(
    'failed Flutter request reports failure instead of completing geometry',
    () async {
      final acknowledgements = <Object>[];
      final handler = FoldOrientationRequests(
        validate: (_) async => true,
        apply: (_) async => throw StateError('platform failure'),
        complete: (id, success) async => acknowledgements.add((id, success)),
      );
      await handler.handle({
        'id': 1,
        'orientations': ['portraitUp'],
      });
      expect(acknowledgements, [(1, false)]);
    },
  );
}
