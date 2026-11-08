import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'direct route preserves arguments, binding and result with safe insets',
    (tester) async {
      Get.testMode = true;
      addTearDown(Get.reset);
      var bound = false;
      late double remainingRight;
      await tester.pumpWidget(
        GetMaterialApp(
          home: const Scaffold(body: Text('home')),
          builder: (context, child) => MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(right: 84),
              viewPadding: EdgeInsets.only(right: 84),
            ),
            child: child!,
          ),
        ),
      );
      final result = Get.toSafe<int>(
        () => ViewSafeArea(
          child: Builder(
            builder: (context) {
              remainingRight = MediaQuery.viewPaddingOf(context).right;
              return const SizedBox.expand(key: Key('direct-body'));
            },
          ),
        ),
        routeName: '/direct-safe',
        arguments: 7,
        binding: BindingsBuilder(() => bound = true),
      );
      await tester.pumpAndSettle();
      expect(bound, true);
      expect(Get.arguments, 7);
      expect(Get.currentRoute, '/direct-safe');
      expect(remainingRight, 0);
      expect(tester.getSize(find.byKey(const Key('direct-body'))).width, 716);
      Get.back(result: 42);
      await tester.pumpAndSettle();
      expect(await result, 42);
    },
  );
}
