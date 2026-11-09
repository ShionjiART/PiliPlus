import 'dart:io';
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/rail_page_view.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/simple_app_bar.dart';
import 'package:PiliPlus/common/widgets/sliver/video_header.dart';
import 'package:PiliPlus/pages/video/widgets/collapsed_video_toolbar.dart';
import 'package:PiliPlus/pages/video/widgets/video_detail_body_insets.dart';
import 'package:PiliPlus/utils/ios/native_tab_bar.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _video = Key('video-frame');
const _more = Key('more');
const _resume = Key('resume');
const _details = Key('details');

class _VideoProbe extends StatefulWidget {
  const _VideoProbe({super.key});
  @override
  State<_VideoProbe> createState() => _VideoProbeState();
}

class _VideoProbeState extends State<_VideoProbe> {
  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Color(0xff285e84));
}

void main() {
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
  Future<void> render(
    WidgetTester tester, {
    bool edge = true,
    bool full = false,
    double scale = 1,
    Size nativeSize = const Size(466, 678),
    ScrollController? scroll,
    Key? playerKey,
    Key? boundary,
  }) async {
    tester.view.physicalSize = nativeSize / scale * 2;
    tester.view.devicePixelRatio = 2;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: RepaintBoundary(
          key: boundary,
          child: NativeSafeArea(
            scale: scale,
            child: Builder(
              builder: (context) {
                final outer =
                    IOSNativeTabBar.rightRailDevice.value &&
                    isOuterPortraitVideoLayout(
                      windowSize: nativeSize,
                      isIPhone: true,
                      hasSideBar: true,
                    );
                return StableVideoViewport(
                  enabled: IOSNativeTabBar.rightRailDevice.value && !full,
                  windowSize: MediaQuery.sizeOf(context),
                  edgeToEdgeTop: edge && outer,
                  child: Builder(
                    builder: (context) {
                      final width = MediaQuery.sizeOf(context).width;
                      final height = width * 9 / 16;
                      final top = edge && outer
                          ? RailViewportScope.of(context)!.insets.top
                          : 0.0;
                      return SimpleScaffold(
                        backgroundColor: Colors.black,
                        appBar: SimpleAppBar(
                          height: MediaQuery.viewPaddingOf(context).top,
                          brightness: Brightness.dark,
                        ),
                        body: CustomScrollView(
                          controller: scroll,
                          slivers: [
                            VideoHeader(
                              minExtent: kToolbarHeight,
                              maxExtent: height,
                              minVideoHeight: height,
                              onScrollRatioChanged: (_) {},
                              child: Stack(
                                children: [
                                  SizedBox(
                                    key: _video,
                                    width: width,
                                    height: height,
                                    child: _VideoProbe(key: playerKey),
                                  ),
                                  Positioned.fill(
                                    child: CollapsedVideoToolbar(
                                      fullScreen: full,
                                      topInset: top,
                                      leading: const SizedBox.shrink(),
                                      title: const Text('继续播放', key: _resume),
                                      trailing: const SizedBox(
                                        key: _more,
                                        width: 42,
                                        height: 34,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: VideoDetailBodyInsets(
                                extendRight: false,
                                fullScreen: full,
                                child: const SizedBox(
                                  key: _details,
                                  height: 1200,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  void reset(WidgetTester tester) {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> capture(
    WidgetTester tester,
    GlobalKey boundary,
    String name,
  ) async {
    const directory = String.fromEnvironment('PILI_LAYOUT_EVIDENCE_DIR');
    if (directory.isEmpty) return;
    await tester.runAsync(() async {
      final box =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await box.toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      img.dispose();
    });
  }

  testWidgets(
    'removes the 12pt outer video gutter without cropping the frame',
    (tester) async {
      reset(tester);
      final boundary = GlobalKey();
      await render(tester, edge: false, boundary: boundary);
      final before = tester.getRect(find.byKey(_video));
      expect(before.top, 12);
      expect(before.size, const Size(466, 466 * 9 / 16));
      await capture(tester, boundary, 'v21-video-top-before');
      await render(tester, boundary: boundary);
      final after = tester.getRect(find.byKey(_video));
      expect(after.top, 0);
      expect(after.size, before.size);
      expect(tester.getRect(find.byKey(_details)).right, 466 - 76);
      await capture(tester, boundary, 'v22-video-top-after');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('status changes, folding and fullscreen retain the video state', (
    tester,
  ) async {
    reset(tester);
    const playerKey = Key('live-player');
    await render(tester, playerKey: playerKey);
    final state = tester.state(find.byKey(playerKey));
    final original = tester.getRect(find.byKey(_video));
    for (final top in [0.0, 24.0, 12.0]) {
      IOSNativeTabBar.safeArea.value = EdgeInsets.only(top: top, right: 84);
      await tester.pump();
      expect(tester.getRect(find.byKey(_video)), original);
      expect(tester.state(find.byKey(playerKey)), same(state));
    }
    IOSNativeTabBar.playerFullScreen.value = true;
    await render(tester, full: true, playerKey: playerKey);
    expect(tester.getRect(find.byKey(_video)).top, 0);
    expect(tester.getRect(find.byKey(_details)).right, 466);
    expect(tester.state(find.byKey(playerKey)), same(state));
    IOSNativeTabBar.playerFullScreen.value = false;
    await render(
      tester,
      nativeSize: const Size(951, 669),
      playerKey: playerKey,
    );
    expect(tester.getRect(find.byKey(_video)).top, 12);
    expect(tester.state(find.byKey(playerKey)), same(state));
    await render(tester, playerKey: playerKey);
    expect(tester.getRect(find.byKey(_video)).top, 0);
    expect(tester.state(find.byKey(playerKey)), same(state));
    IOSNativeTabBar.rightRailDevice.value = false;
    IOSNativeTabBar.safeArea.value = const EdgeInsets.only(top: 59);
    await render(tester, playerKey: playerKey);
    expect(tester.getRect(find.byKey(_video)).top, 59);
    expect(tester.state(find.byKey(playerKey)), same(state));
  });
  testWidgets(
    'collapsed controls keep their own top and side avoidance across scales',
    (tester) async {
      reset(tester);
      for (final scale in [0.8, 1.0, 1.5]) {
        final scroll = ScrollController();
        await render(tester, scale: scale, scroll: scroll);
        final frame = tester.getRect(find.byKey(_video));
        expect(frame.top, 0);
        expect(frame.width / frame.height, closeTo(16 / 9, 0.001));
        scroll.jumpTo(frame.height - kToolbarHeight);
        await tester.pump();
        final more = tester.getRect(find.byKey(_more));
        expect(more.right, closeTo((466 - 76) / scale, 0.001));
        expect(more.top, closeTo(11 + 6 / scale, 0.001));
        expect(more.top, greaterThanOrEqualTo(12 / scale));
        expect(more.bottom, lessThanOrEqualTo(kToolbarHeight));
        expect(
          tester.getCenter(find.byKey(_resume)).dx,
          closeTo((466 - 76) / scale / 2, 0.001),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        scroll.dispose();
      }
    },
  );
}
