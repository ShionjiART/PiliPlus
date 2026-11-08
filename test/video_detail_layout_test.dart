import 'package:PiliPlus/utils/ios/native_tab_bar.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/pages/video/widgets/video_detail_body_insets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'fullscreen releases the native right inset for all overlays and restores it',
    (tester) async {
      IOSNativeTabBar.safeArea.value = const EdgeInsets.fromLTRB(
        12,
        24,
        84,
        20,
      );
      IOSNativeTabBar.rightRailDevice.value = true;
      addTearDown(() {
        IOSNativeTabBar.safeArea.value = null;
        IOSNativeTabBar.rightRailDevice.value = false;
        IOSNativeTabBar.playerFullScreen.value = false;
      });
      late MediaQueryData observed;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: NativeSafeArea(
            scale: 1,
            child: Builder(
              builder: (context) {
                observed = MediaQuery.of(context);
                return const _PlayerStateProbe(key: Key('player'));
              },
            ),
          ),
        ),
      );
      final state = tester.state(find.byKey(const Key('player')));
      expect(observed.viewPadding.right, 76);
      IOSNativeTabBar.playerFullScreen.value = true;
      await tester.pump();
      expect(observed.padding.right, 0);
      expect(observed.viewPadding.right, 0);
      expect(observed.padding.left, 12);
      expect(tester.state(find.byKey(const Key('player'))), same(state));
      IOSNativeTabBar.playerFullScreen.value = false;
      await tester.pump();
      expect(observed.viewPadding.right, 76);
    },
  );
  testWidgets(
    'compact rail clearance consumes once, follows scale and leaves other devices unchanged',
    (tester) async {
      IOSNativeTabBar.safeArea.value = const EdgeInsets.fromLTRB(
        12,
        24,
        84,
        20,
      );
      IOSNativeTabBar.rightRailDevice.value = false;
      addTearDown(() {
        IOSNativeTabBar.safeArea.value = null;
        IOSNativeTabBar.rightRailDevice.value = false;
        IOSNativeTabBar.playerFullScreen.value = false;
      });
      late MediaQueryData observed;
      Future<void> render(double scale) => tester.pumpWidget(
        MaterialApp(
          home: NativeSafeArea(
            scale: scale,
            child: SideSafeArea(
              child: Builder(
                builder: (context) {
                  observed = MediaQuery.of(context);
                  return const _PlayerStateProbe(key: Key('compact-content'));
                },
              ),
            ),
          ),
        ),
      );
      await render(1);
      expect(
        tester.getRect(find.byKey(const Key('compact-content'))).right,
        716,
      );
      final state = tester.state(find.byKey(const Key('compact-content')));
      IOSNativeTabBar.rightRailDevice.value = true;
      await tester.pump();
      final contentRight = tester
          .getRect(find.byKey(const Key('compact-content')))
          .right;
      expect(contentRight, 724);
      expect(800 - 72 - contentRight, 4);
      expect(
        observed.viewPadding.right,
        0,
      ); // Nested safe areas cannot add it twice.
      expect(
        tester.state(find.byKey(const Key('compact-content'))),
        same(state),
      );
      for (final scale in [0.8, 1.3]) {
        await render(scale);
        expect(
          tester.getRect(find.byKey(const Key('compact-content'))).right,
          closeTo(800 - 76 / scale, 0.001),
        );
        expect(observed.viewPadding.right, 0);
      }
      IOSNativeTabBar.rightRailDevice.value = false;
      await render(1);
      expect(
        tester.getRect(find.byKey(const Key('compact-content'))).right,
        716,
      );
    },
  );

  testWidgets(
    'portrait video can reach the right edge while details stop before the rail',
    (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: MediaQueryData(
              padding: EdgeInsets.only(right: 84),
              viewPadding: EdgeInsets.only(right: 84),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 250,
                  width: double.infinity,
                  key: Key('video'),
                ),
                Expanded(
                  child: VideoDetailBodyInsets(
                    extendRight: false,
                    child: ViewSafeArea(
                      child: SizedBox.expand(key: Key('details')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.getRect(find.byKey(const Key('video'))).right, 800);
      expect(tester.getRect(find.byKey(const Key('details'))).right, 716);
    },
  );
  testWidgets('fullscreen bypass retains the active player state', (
    tester,
  ) async {
    const playerKey = Key('player');
    Future<void> render(bool enabled) => tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(viewPadding: EdgeInsets.only(top: 24)),
        child: StableVideoViewport(
          enabled: enabled,
          windowSize: const Size(466, 678),
          child: _PlayerStateProbe(key: playerKey),
        ),
      ),
    );
    await render(true);
    final playerState = tester.state(find.byKey(playerKey));
    await render(false);
    expect(tester.state(find.byKey(playerKey)), same(playerState));
    await render(true);
    expect(tester.state(find.byKey(playerKey)), same(playerState));
  });

  testWidgets('video and lower content stay still as status chrome fades', (
    tester,
  ) async {
    Future<void> render(
      double top, {
      bool enabled = true,
      double keyboard = 0,
    }) => tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(466, 678),
            padding: EdgeInsets.only(
              top: top,
              right: 84,
              bottom: keyboard > 0 ? 0 : 34,
            ),
            viewPadding: EdgeInsets.only(top: top, right: 84, bottom: 34),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: StableVideoViewport(
            enabled: enabled,
            windowSize: const Size(466, 678),
            child: Builder(
              builder: (context) {
                final padding = MediaQuery.paddingOf(context);
                return Padding(
                  padding: EdgeInsets.only(
                    top: padding.top,
                    bottom: padding.bottom,
                  ),
                  child: Column(
                    children: const [
                      SizedBox(height: 260, key: Key('video')),
                      Expanded(child: SizedBox.expand(key: Key('details'))),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await render(24);
    final video = tester.getRect(find.byKey(const Key('video')));
    final details = tester.getRect(find.byKey(const Key('details')));
    for (final top in [0.0, 24.0, 0.0, 24.0]) {
      await render(top);
      expect(tester.getRect(find.byKey(const Key('video'))), video);
      expect(tester.getRect(find.byKey(const Key('details'))), details);
    }
    await render(0, enabled: false);
    expect(tester.getTopLeft(find.byKey(const Key('video'))).dy, 0);
    await render(0);
    expect(tester.getRect(find.byKey(const Key('video'))), video);
    await render(0, keyboard: 300);
    expect(tester.getTopLeft(find.byKey(const Key('video'))).dy, 24);
    expect(tester.getBottomRight(find.byKey(const Key('details'))).dy, 600);
  });

  testWidgets('a real resize or UI scale change refreshes the safe baseline', (
    tester,
  ) async {
    late MediaQueryData observed;
    Future<void> render(Size size, double top, double scale) =>
        tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              devicePixelRatio: scale,
              viewPadding: EdgeInsets.only(top: top, right: 84),
              padding: EdgeInsets.only(top: top, right: 84),
            ),
            child: StableVideoViewport(
              enabled: true,
              windowSize: size,
              child: Builder(
                builder: (context) {
                  observed = MediaQuery.of(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        );
    await render(const Size(466, 678), 24, 3);
    await render(const Size(466, 678), 0, 3);
    expect(observed.padding.top, 24);
    await render(const Size(890, 626), 12, 3);
    expect(observed.padding.top, 12);
    await render(const Size(890, 626), 0, 3);
    expect(observed.padding.top, 12);
    await render(const Size(890, 626), 8, 2);
    expect(observed.padding.top, 8);
    expect(observed.viewPadding.right, 84);
  });

  test(
    'outer display keeps its portrait template across host-height changes',
    () {
      // A horizontal-mode aspect-ratio threshold used to change templates when
      // the native bars adjusted the host's height.
      for (final height in [678.0, 634.0]) {
        expect(
          isOuterPortraitVideoLayout(
            windowSize: Size(466, height),
            isIPhone: true,
            hasSideBar: true,
          ),
          true,
        );
      }
      expect(
        isOuterPortraitVideoLayout(
          windowSize: const Size(626, 890),
          isIPhone: true,
          hasSideBar: true,
        ),
        false,
      );
      expect(
        isOuterPortraitVideoLayout(
          windowSize: const Size(466, 678),
          isIPhone: true,
          hasSideBar: false,
        ),
        false,
      );
      expect(
        isOuterPortraitVideoLayout(
          windowSize: const Size(678, 466),
          isIPhone: true,
          hasSideBar: true,
        ),
        false,
      );
    },
  );

  testWidgets(
    'outer details reserve the rail exactly once as right inset changes',
    (tester) async {
      for (final right in [84.0, 72.0, 84.0]) {
        late EdgeInsets remaining;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                padding: EdgeInsets.only(left: 12, right: right),
                viewPadding: EdgeInsets.only(left: 12, right: right),
              ),
              child: VideoDetailBodyInsets(
                extendRight: false,
                child: ViewSafeArea(
                  child: Builder(
                    builder: (context) {
                      remaining = MediaQuery.viewPaddingOf(context);
                      return const SizedBox.expand(key: Key('body'));
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        expect(
          tester.getRect(find.byKey(const Key('body'))),
          Rect.fromLTWH(12, 0, 788 - right, 600),
        );
        expect(remaining.horizontal, 0);
      }
    },
  );

  testWidgets('ordinary video layout continues to avoid both side insets', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            padding: EdgeInsets.only(left: 12, right: 84),
            viewPadding: EdgeInsets.only(left: 12, right: 84),
          ),
          child: VideoDetailBodyInsets(
            extendRight: false,
            child: SizedBox.expand(key: Key('body')),
          ),
        ),
      ),
    );
    expect(
      tester.getRect(find.byKey(const Key('body'))),
      const Rect.fromLTWH(12, 0, 704, 600),
    );
  });
}

class _PlayerStateProbe extends StatefulWidget {
  const _PlayerStateProbe({super.key});

  @override
  State<_PlayerStateProbe> createState() => _PlayerStateProbeState();
}

class _PlayerStateProbeState extends State<_PlayerStateProbe> {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
