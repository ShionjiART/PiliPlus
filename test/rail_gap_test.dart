import 'dart:io';
import 'dart:ui' as ui;

import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/rail_page_view.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/ios/native_tab_bar.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'visible home card-to-rail clearance is exactly 4 native points',
    (tester) async {
      tester.view.physicalSize = const Size(466 * 2, 678 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      IOSNativeTabBar.rightRailDevice.value = true;
      IOSNativeTabBar.safeArea.value = const EdgeInsets.only(right: 84);
      addTearDown(() {
        IOSNativeTabBar.safeArea.value = null;
        IOSNativeTabBar.rightRailDevice.value = false;
      });
      final boundaryKey = GlobalKey();
      const cardKey = Key('right-card');
      const railKey = Key('rail');
      Widget grid() => CustomScrollView(
        slivers: [
          SliverGrid(
            gridDelegate: SliverGridDelegateWithExtentAndRatio(
              maxCrossAxisExtent: 200,
              crossAxisSpacing: Style.cardSpace,
              mainAxisSpacing: Style.cardSpace,
              mainAxisExtent: 90,
              childAspectRatio: Style.aspectRatio,
            ),
            delegate: SliverChildListDelegate([
              const ColoredBox(
                color: Color(0xff244b65),
                child: SizedBox.expand(),
              ),
              const ColoredBox(
                color: Color(0xff244b65),
                child: SizedBox.expand(),
              ),
              const ColoredBox(
                color: Color(0xff244b65),
                child: SizedBox.expand(),
              ),
              const ColoredBox(
                key: cardKey,
                color: Color(0xff244b65),
                child: SizedBox.expand(),
              ),
            ]),
          ),
        ],
      );
      Future<void> render(bool baseline) => tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: RepaintBoundary(
            key: boundaryKey,
            child: Stack(
              children: [
                Positioned.fill(
                  child: baseline
                      ? Padding(
                          padding: const EdgeInsets.only(right: 74),
                          child: Container(
                            margin: const EdgeInsets.only(left: 12),
                            child: grid(),
                          ),
                        )
                      : NativeSafeArea(
                          scale: 1,
                          child: Builder(
                            builder: (context) => Padding(
                              padding: EdgeInsets.only(
                                right: MediaQuery.viewPaddingOf(context).right,
                              ),
                              child: RailFeedFrame(child: grid()),
                            ),
                          ),
                        ),
                ),
                Positioned(
                  right: 24,
                  top: 220,
                  width: 48,
                  height: 170,
                  child: DecoratedBox(
                    key: railKey,
                    decoration: BoxDecoration(
                      color: const Color(0xff353535),
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      Future<void> capture(String name) async {
        const directory = String.fromEnvironment('PILI_LAYOUT_EVIDENCE_DIR');
        if (directory.isEmpty) return;
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(directory).create(recursive: true);
          await File('$directory/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await render(true);
      final before =
          tester.getRect(find.byKey(railKey)).left -
          tester.getRect(find.byKey(cardKey)).right;
      expect(before, 2);
      await capture('v19-gap-before');
      await render(false);
      final after =
          tester.getRect(find.byKey(railKey)).left -
          tester.getRect(find.byKey(cardKey)).right;
      expect(after, 4);
      expect(tester.getRect(find.byKey(cardKey)).left, greaterThan(12));
      await capture('v20-gap-after');
      expect(tester.takeException(), isNull);
    },
  );
}
