import 'package:PiliPlus/utils/ios/native_tab_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'Flutter back follows actual native visibility and keeps custom actions',
    (tester) async {
      final key = GlobalKey<NavigatorState>();
      IOSNativeTabBar.backButtonVisible.value = false;
      addTearDown(() => IOSNativeTabBar.backButtonVisible.value = false);
      await tester.pumpWidget(
        NativeBackScope(
          child: MaterialApp(
            navigatorKey: key,
            home: const Scaffold(body: Text('home')),
          ),
        ),
      );
      key.currentState!.push(
        MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: !IOSNativeTabBar.hasNativeBack(
                context,
              ),
              title: const Text('page'),
              actions: [
                IconButton(icon: const Icon(Icons.save), onPressed: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);
      IOSNativeTabBar.backButtonVisible.value = true;
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsNothing);
      expect(find.byIcon(Icons.save), findsOneWidget);
      // Rotation back to a top status bar restores the in-page button.
      IOSNativeTabBar.backButtonVisible.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);
    },
  );
}
