import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/simple_app_bar.dart';
import 'package:PiliPlus/common/widgets/sliver/video_header.dart';
import 'package:PiliPlus/pages/video/widgets/collapsed_video_toolbar.dart';
import 'package:PiliPlus/pages/video/widgets/video_detail_body_insets.dart';
import 'package:PiliPlus/utils/ios/native_tab_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const video = Key('video');
  const title = Key('resume');
  const more = Key('more');
  const back = Key('back');
  setUp(() {
    IOSNativeTabBar.rightRailDevice.value = true;
    IOSNativeTabBar.safeArea.value = const EdgeInsets.only(top: 24, right: 84);
    IOSNativeTabBar.playerFullScreen.value = false;
  });
  tearDown(() {
    IOSNativeTabBar.rightRailDevice.value = false;
    IOSNativeTabBar.safeArea.value = null;
    IOSNativeTabBar.playerFullScreen.value = false;
  });
  testWidgets(
    'paused collapsed header avoids the rail without narrowing video',
    (tester) async {
      tester.view.physicalSize = const Size(466 * 2, 678 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final scale in [0.8, 1.0, 1.5]) {
        final scroll = ScrollController();
        var moreCalls = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: NativeSafeArea(
              scale: scale,
              child: Builder(
                builder: (context) => SimpleScaffold(
                  appBar: SimpleAppBar(
                    height: MediaQuery.paddingOf(context).top,
                    brightness: Brightness.dark,
                  ),
                  body: CustomScrollView(
                    controller: scroll,
                    slivers: [
                      VideoHeader(
                        minExtent: kToolbarHeight,
                        maxExtent: 400,
                        minVideoHeight: 262,
                        onScrollRatioChanged: (_) {},
                        child: Stack(
                          children: [
                            const SizedBox(
                              key: video,
                              width: double.infinity,
                              height: 400,
                            ),
                            Positioned.fill(
                              child: CollapsedVideoToolbar(
                                fullScreen: false,
                                leading: const SizedBox.shrink(),
                                title: const Text('继续播放', key: title),
                                trailing: SizedBox(
                                  key: more,
                                  width: 42,
                                  height: 34,
                                  child: IconButton(
                                    onPressed: () => moreCalls++,
                                    icon: const Icon(Icons.more_vert),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 2000)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        scroll.jumpTo(344);
        await tester.pump();
        final rect = tester.getRect(find.byKey(more));
        expect(rect.right, closeTo(466 - 76 / scale, 0.001));
        expect((466 - 72 / scale - rect.right) * scale, closeTo(4, 0.001));
        expect(rect.top, closeTo(12 / scale + 11, 0.001));
        expect(
          tester.getCenter(find.byKey(title)).dx,
          closeTo((466 - 76 / scale) / 2, 0.001),
        );
        expect(tester.getSize(find.byKey(video)).width, 466);
        await tester.tap(find.byKey(more));
        expect(moreCalls, 1);
        IOSNativeTabBar.safeArea.value = const EdgeInsets.only(right: 96);
        await tester.pump();
        expect(tester.getRect(find.byKey(more)), rect);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        scroll.dispose();
      }
    },
  );
  testWidgets(
    'nested safe area is consumed once and fullscreen preserves controls',
    (tester) async {
      Future<void> render(bool full) => tester.pumpWidget(
        MaterialApp(
          home: NativeSafeArea(
            scale: 1,
            child: VideoDetailBodyInsets(
              extendRight: false,
              fullScreen: full,
              child: CollapsedVideoToolbar(
                fullScreen: full,
                leading: const SizedBox(key: back, width: 42, height: 34),
                title: const Text('继续播放', key: title),
                trailing: const SizedBox(key: more, width: 42, height: 34),
              ),
            ),
          ),
        ),
      );
      await render(false);
      final element = tester.element(find.byKey(more));
      expect(tester.getRect(find.byKey(more)).right, 800 - 76);
      IOSNativeTabBar.playerFullScreen.value = true;
      await render(true);
      expect(tester.getRect(find.byKey(more)).right, 800);
      expect(tester.element(find.byKey(more)), same(element));
      IOSNativeTabBar.playerFullScreen.value = false;
      await render(false);
      expect(tester.getRect(find.byKey(more)).right, 800 - 76);
      expect(tester.element(find.byKey(more)), same(element));
    },
  );
  testWidgets('ordinary left and right insets remain respected', (
    tester,
  ) async {
    Future<void> render(bool full) => tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(left: 24, right: 34),
            viewPadding: EdgeInsets.only(left: 24, right: 34),
          ),
          child: CollapsedVideoToolbar(
            fullScreen: full,
            leading: const SizedBox(key: back, width: 42, height: 34),
            title: const Text('继续播放'),
            trailing: const SizedBox(key: more, width: 42, height: 34),
          ),
        ),
      ),
    );
    await render(false);
    expect(tester.getRect(find.byKey(back)).left, 24);
    expect(tester.getRect(find.byKey(more)).right, 800 - 34);
    await render(true);
    expect(tester.getRect(find.byKey(back)).left, 0);
    expect(tester.getRect(find.byKey(more)).right, 800);
  });
}
