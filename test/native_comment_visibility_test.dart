import 'package:PiliPlus/utils/ios/native_tab_bar.dart';
import 'package:PiliPlus/common/widgets/native_comment_button.dart';
import 'package:PiliPlus/pages/video/widgets/video_detail_body_insets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'hidden, translated and clipped comment anchors cannot claim the native slot',
    (tester) async {
      final key = GlobalKey();
      Widget anchor() => SizedBox(key: key, width: 56, height: 56);
      Future<bool> visible(Widget child) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(alignment: Alignment.topLeft, child: child),
          ),
        );
        return isCommentAnchorVisible(
          key.currentContext!.findRenderObject()! as RenderBox,
        );
      }

      expect(await visible(anchor()), true);
      expect(await visible(Offstage(child: anchor())), false);
      expect(await visible(Opacity(opacity: 0, child: anchor())), false);
      expect(
        await visible(
          Transform.translate(offset: const Offset(0, 700), child: anchor()),
        ),
        false,
      );
      // Still inside the window, but outside its tab/panel's paint clip.
      expect(
        await visible(
          SizedBox(
            width: 100,
            height: 100,
            child: ClipRect(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(left: 110, top: 0, child: anchor()),
                ],
              ),
            ),
          ),
        ),
        false,
      );
    },
  );

  testWidgets('native compose stays visible after scroll-hide animation', (
    tester,
  ) async {
    final old = IOSNativeTabBar.rightRailDevice.value;
    IOSNativeTabBar.rightRailDevice.value = true;
    addTearDown(() => IOSNativeTabBar.rightRailDevice.value = old);
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.bottomRight,
          child: CommentFabTransition(
            position: const AlwaysStoppedAnimation(Offset(0, 1)),
            child: SizedBox(key: key, width: 56, height: 56),
          ),
        ),
      ),
    );
    expect(
      isCommentAnchorVisible(
        key.currentContext!.findRenderObject()! as RenderBox,
      ),
      true,
    );
    expect(tester.getBottomRight(find.byKey(key)), const Offset(800, 600));
    IOSNativeTabBar.rightRailDevice.value = false;
    await tester.pump();
    expect(
      isCommentAnchorVisible(
        key.currentContext!.findRenderObject()! as RenderBox,
      ),
      false,
    );
  });

  test(
    'outer video leaves native controls and compose room across UI scales',
    () {
      for (final scale in [0.8, 1.0, 1.3]) {
        final limit = outerVideoHeightLimit(
          height: 678 / scale,
          insets: EdgeInsets.only(top: 20 / scale, bottom: 12 / scale),
          uiScale: scale,
        );
        final nativeBottom = (limit + 20 / scale) * scale;
        expect(
          nativeBottom + 8 + 3 * 44 + 2 * 8,
          lessThanOrEqualTo(678 - 12 - 60),
        );
      }
    },
  );
}
