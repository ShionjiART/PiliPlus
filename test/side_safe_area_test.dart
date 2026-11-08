import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final right in [0.0, 84.0]) {
    testWidgets('side inset $right is consumed exactly once', (tester) async {
      late EdgeInsets remainingPadding;
      late EdgeInsets remainingViewPadding;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              padding: EdgeInsets.only(top: 24, right: right, bottom: 20),
              viewPadding: EdgeInsets.only(top: 24, right: right, bottom: 20),
            ),
            child: SideSafeArea(
              child: ViewSafeArea(
                child: Builder(
                  builder: (context) {
                    remainingPadding = MediaQuery.paddingOf(context);
                    remainingViewPadding = MediaQuery.viewPaddingOf(context);
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
        Rect.fromLTWH(0, 0, 800 - right, 600),
      );
      expect(remainingPadding, const EdgeInsets.only(top: 24, bottom: 20));
      expect(remainingViewPadding, const EdgeInsets.only(top: 24, bottom: 20));
    });
  }
}
