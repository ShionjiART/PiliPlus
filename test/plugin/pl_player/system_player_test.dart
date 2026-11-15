import 'package:PiliPlus/plugin/pl_player/system_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SystemPlayer.interpolate', () {
    Duration run({
      int last = 10000,
      int elapsed = 100,
      double rate = 1,
      bool advancing = true,
      int duration = 0,
    }) => SystemPlayer.interpolate(
      last: Duration(milliseconds: last),
      elapsed: Duration(milliseconds: elapsed),
      rate: rate,
      advancing: advancing,
      duration: Duration(milliseconds: duration),
    );

    test('advances by elapsed time at the playback rate', () {
      expect(run(), const Duration(milliseconds: 10100));
      expect(run(rate: 2), const Duration(milliseconds: 10200));
      expect(run(rate: 0.5), const Duration(milliseconds: 10050));
    });

    test('stays at the last position while paused or buffering', () {
      expect(run(advancing: false), const Duration(milliseconds: 10000));
      expect(
        run(advancing: false, elapsed: 60000),
        const Duration(milliseconds: 10000),
      );
    });

    test('runs ahead of the last update by at most maxInterpolation', () {
      const max = SystemPlayer.maxInterpolation;
      expect(run(elapsed: 60000), const Duration(milliseconds: 10000) + max);
      expect(
        run(elapsed: 400, rate: 2),
        const Duration(milliseconds: 10000) + max,
      );
    });

    test('never passes the duration', () {
      expect(
        run(last: 9900, elapsed: 400, duration: 10000),
        const Duration(milliseconds: 10000),
      );
      // Unknown duration: no limit.
      expect(
        run(last: 9900, elapsed: 400),
        const Duration(milliseconds: 10300),
      );
    });
  });

  group('SystemPlayer events', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('piliplus/system_player');
    const events = EventChannel('piliplus/system_player/events');
    late MockStreamHandlerEventSink sink;

    setUpAll(() {
      messenger
        ..setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'create') return 7;
          return null;
        })
        ..setMockStreamHandler(
          events,
          MockStreamHandler.inline(onListen: (_, s) => sink = s),
        );
    });

    tearDownAll(() {
      messenger
        ..setMockMethodCallHandler(channel, null)
        ..setMockStreamHandler(events, null);
    });

    Future<void> emit(String type, Map<String, Object> payload) async {
      sink.success({'id': 7, 'type': type, ...payload});
      await pumpEventQueue();
    }

    test('position stops advancing while buffering', () async {
      final player = await SystemPlayer.create();
      final subs = [
        player.position.listen((_) {}),
        player.playing.listen((_) {}),
        player.buffering.listen((_) {}),
        player.duration.listen((_) {}),
      ];
      await pumpEventQueue();

      await emit('duration', {'ms': 60000});
      await emit('playing', {'value': true});
      await emit('position', {'ms': 5000, 'bufferedMs': 6000});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final playing = player.currentPosition;
      expect(playing, greaterThan(const Duration(milliseconds: 5000)));
      expect(
        playing,
        lessThanOrEqualTo(
          const Duration(milliseconds: 5000) + SystemPlayer.maxInterpolation,
        ),
      );

      // Stalled: still "playing" (waiting to play), but time stands still.
      await emit('buffering', {'value': true});
      expect(player.currentPosition, const Duration(milliseconds: 5000));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(player.currentPosition, const Duration(milliseconds: 5000));

      // Resumed: counts from now, not from before the stall.
      await emit('buffering', {'value': false});
      final resumed = player.currentPosition;
      expect(
        resumed,
        lessThan(const Duration(milliseconds: 5000 + 40)),
        reason: 'the stall must not count as played time',
      );

      // Paused: stays put.
      await emit('playing', {'value': false});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(player.currentPosition, const Duration(milliseconds: 5000));

      for (final s in subs) {
        await s.cancel();
      }
    });
  });
}
