import 'package:PiliPlus/common/widgets/appbar/rail_floating_app_bar.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/rail_page_view.dart';
import 'package:PiliPlus/common/widgets/home_tools_slot.dart';
import 'package:PiliPlus/utils/ios/native_tab_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUp(() {
    IOSNativeTabBar.rightRailDevice.value = true;
    IOSNativeTabBar.safeArea.value = const EdgeInsets.only(top: 24, right: 84);
    IOSNativeTabBar.playerFullScreen.value = false;
  });
  tearDown(() {
    IOSNativeTabBar.safeArea.value = null;
    IOSNativeTabBar.rightRailDevice.value = false;
    IOSNativeTabBar.playerFullScreen.value = false;
  });
  testWidgets('rail top remains 12 through status changes and scales once', (
    tester,
  ) async {
    late MediaQueryData query;
    bool normalized = false;
    Future<void> render(double scale) => tester.pumpWidget(
      MaterialApp(
        home: NativeSafeArea(
          scale: scale,
          child: Builder(
            builder: (context) {
              query = MediaQuery.of(context);
              normalized = RailViewportScope.of(context)!.normalizedTop;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await render(1);
    expect(query.padding.top, 12);
    expect(normalized, isTrue);
    IOSNativeTabBar.safeArea.value = const EdgeInsets.only(right: 84);
    await tester.pump();
    expect(query.padding.top, 12);
    await render(1.5);
    expect(query.padding.top, 8);
    expect(
      homeTopSpacing(
        12,
        HomeToolsPlacement.rightRail,
        alreadyNormalized: true,
      ),
      12,
    );
    IOSNativeTabBar.playerFullScreen.value = true;
    await tester.pump();
    expect(query.padding.top, 0);
    expect(query.padding.right, 0);
    IOSNativeTabBar.playerFullScreen.value = false;
    IOSNativeTabBar.safeArea.value = const EdgeInsets.only(top: 59);
    await render(1);
    expect(query.padding.top, 59);
    expect(normalized, isFalse);
  });
  testWidgets(
    'floating author bar does not reserve a toolbar or recreate body',
    (tester) async {
      const bodyKey = Key('body');
      const firstKey = Key('first');
      const headerKey = Key('header');
      int tapped = 0;
      Future<void> render(bool floating, bool visible) => tester.pumpWidget(
        MaterialApp(
          home: NativeSafeArea(
            scale: 1,
            child: SimpleScaffold(
              overlayAppBar: floating,
              appBar: RailFloatingAppBar(
                overlay: floating,
                visible: visible,
                child: AppBar(
                  title: TextButton(
                    key: headerKey,
                    onPressed: () => tapped++,
                    child: const Text('作者'),
                  ),
                ),
              ),
              body: ListView(
                key: bodyKey,
                children: const [SizedBox(key: firstKey, height: 120)],
              ),
            ),
          ),
        ),
      );
      await render(false, true);
      expect(tester.getTopLeft(find.byKey(firstKey)).dy, 68);
      final body = tester.element(find.byKey(bodyKey));
      await render(true, false);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(firstKey)).dy, 12);
      expect(tester.element(find.byKey(bodyKey)), same(body));
      await tester.tap(find.byKey(headerKey), warnIfMissed: false);
      expect(tapped, 0);
      await render(true, true);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(firstKey)).dy, 12);
      expect(tester.element(find.byKey(bodyKey)), same(body));
      await tester.tap(find.byKey(headerKey));
      expect(tapped, 1);
      await render(true, false);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(firstKey)).dy, 12);
    },
  );
}
