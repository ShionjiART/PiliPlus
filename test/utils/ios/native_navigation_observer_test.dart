import 'package:PiliPlus/utils/ios/native_navigation_observer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late NativeNavigationObserver observer;
  late List<bool> canGoBack;
  late List<String?> topNames;
  final navigatorKey = GlobalKey<NavigatorState>();

  Future<void> pumpApp(WidgetTester tester) async {
    canGoBack = [];
    topNames = [];
    observer = NativeNavigationObserver(
      onCanGoBackChanged: canGoBack.add,
      onTopRouteChanged: (route) => topNames.add(route?.settings.name),
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        home: const SizedBox(),
      ),
    );
  }

  MaterialPageRoute<void> page(String name) => MaterialPageRoute(
    settings: RouteSettings(name: name),
    builder: (_) => const SizedBox(),
  );

  testWidgets('the root page cannot go back', (tester) async {
    await pumpApp(tester);
    expect(observer.canGoBack, isFalse);
    expect(observer.topRoute?.isFirst, isTrue);
  });

  testWidgets('a pushed page can go back, and popping returns', (
    tester,
  ) async {
    await pumpApp(tester);
    navigatorKey.currentState!.push(page('/detail'));
    await tester.pumpAndSettle();
    expect(observer.canGoBack, isTrue);
    expect(topNames.last, '/detail');

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(observer.canGoBack, isFalse);
    expect(canGoBack.last, isFalse);
  });

  testWidgets('a dialog on a root page is not a secondary page', (
    tester,
  ) async {
    await pumpApp(tester);
    final calls = canGoBack.length;
    showDialog<void>(
      context: navigatorKey.currentContext!,
      builder: (_) => const AlertDialog(),
    );
    await tester.pumpAndSettle();
    expect(observer.canGoBack, isFalse);
    expect(canGoBack.length, calls, reason: 'popups are not reported');

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(observer.canGoBack, isFalse);
    expect(canGoBack.length, calls);
  });

  testWidgets('a bottom sheet over a secondary page keeps that page on top', (
    tester,
  ) async {
    await pumpApp(tester);
    navigatorKey.currentState!.push(page('/detail'));
    await tester.pumpAndSettle();
    showModalBottomSheet<void>(
      context: navigatorKey.currentContext!,
      builder: (_) => const SizedBox(height: 100),
    );
    await tester.pumpAndSettle();
    expect(observer.canGoBack, isTrue);
    expect(observer.topRoute?.settings.name, '/detail');
  });

  testWidgets('replacing a page keeps the stack depth', (tester) async {
    await pumpApp(tester);
    navigatorKey.currentState!.push(page('/a'));
    await tester.pumpAndSettle();
    navigatorKey.currentState!.pushReplacement(page('/b'));
    await tester.pumpAndSettle();
    expect(observer.canGoBack, isTrue);
    expect(observer.topRoute?.settings.name, '/b');

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(observer.canGoBack, isFalse);
  });
}
