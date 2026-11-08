import 'package:PiliPlus/common/widgets/sliver/video_header.dart';
import 'package:PiliPlus/utils/ios/native_page_actions.dart';
import 'package:PiliPlus/utils/ios/native_tab_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('video entry starts hidden before the page registers its player', () {
    late Map<String, Object> state;
    final registry = NativePageActionRegistry(
      onChanged: (value) => state = value,
    );
    registry.setTopPage(
      Object(),
      initialVideo: const NativeVideoChrome(
        controlsVisible: false,
        fullScreen: false,
        locked: false,
      ),
    );
    expect(state['video'], containsPair('controlsVisible', false));
    registry.setTopPage(Object());
    expect(state['video'], false);
  });
  test(
    'video rail commands persist with controls hidden but not in fullscreen',
    () async {
      late Map<String, Object> state;
      final registry = NativePageActionRegistry(
        onChanged: (value) => state = value,
      );
      final videoPage = Object();
      final overlay = Object();
      var homeCalls = 0;
      void update({
        required bool controls,
        bool locked = false,
        bool fullScreen = false,
      }) => registry.register(
        page: videoPage,
        actions: const [NativePageAction(id: 'home', title: '返回主页')],
        video: NativeVideoChrome(
          controlsVisible: controls,
          locked: locked,
          fullScreen: fullScreen,
        ),
        handler: (_) => homeCalls++,
      );
      registry.setTopPage(videoPage);
      update(controls: false);
      final owner = state['owner'] as int;
      await registry.handle(owner: owner, id: 'home');
      expect(homeCalls, 1);
      update(controls: true, locked: true);
      await registry.handle(owner: owner, id: 'home');
      expect(homeCalls, 2);
      update(controls: true, fullScreen: true);
      await registry.handle(owner: owner, id: 'home');
      expect(homeCalls, 2);
      update(controls: true);
      registry.setTopPage(overlay);
      expect(state['video'], false);
      expect(state['items'], isEmpty);
      await registry.handle(owner: owner, id: 'home');
      expect(homeCalls, 2);
      registry.setTopPage(videoPage);
      await registry.handle(owner: owner, id: 'home');
      expect(homeCalls, 3);
      registry.unregister(videoPage);
      expect(state['video'], false);
    },
  );

  testWidgets(
    'outer header reports collapse and expansion independently of player controls',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final page = Object();
      late Map<String, Object> state;
      final registry = NativePageActionRegistry(
        onChanged: (value) => state = value,
      );
      registry.setTopPage(page);
      var collapsed = false;
      var controls = true;
      var locked = false;
      var paused = false;
      final transitions = <bool>[];
      void publish() => registry.register(
        page: page,
        actions: const [NativePageAction(id: 'home', title: '返回主页')],
        video: NativeVideoChrome(
          controlsVisible: controls,
          fullScreen: false,
          locked: locked,
          collapsed: collapsed,
          paused: paused,
        ),
        handler: (_) {},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CustomScrollView(
            controller: scroll,
            slivers: [
              VideoHeader(
                minExtent: kToolbarHeight,
                maxExtent: 400,
                minVideoHeight: 262,
                onScrollRatioChanged: (_) {},
                onCollapsedChanged: (value) {
                  transitions.add(value);
                  collapsed = value;
                  publish();
                },
                child: const SizedBox(height: 400),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 2000)),
            ],
          ),
        ),
      );
      expect(state['video'], containsPair('collapsed', false));
      scroll.jumpTo(200); // Partially reduced: the video is still expanded.
      await tester.pump();
      expect(transitions, [false]);
      scroll.jumpTo(344);
      await tester.pump();
      expect(state['video'], containsPair('collapsed', true));
      controls = false;
      locked = true;
      publish();
      expect(state['video'], containsPair('collapsed', true));
      scroll.jumpTo(0);
      await tester.pump();
      expect(state['video'], containsPair('collapsed', false));
      expect(transitions, [false, true, false]);
      paused = true;
      publish();
      expect(state['video'], containsPair('paused', true));
      expect(state['video'], containsPair('collapsed', false));
      paused = false;
      publish();
      expect(state['video'], containsPair('paused', false));
      // A new stable frame does not repeatedly publish the same state.
      await tester.pump();
      expect(transitions.length, 3);
    },
  );

  testWidgets(
    'hidden native video chrome does not reveal duplicate in-player navigation',
    (tester) async {
      final key = GlobalKey<NavigatorState>();
      IOSNativeTabBar.backButtonVisible.value = false;
      IOSNativeTabBar.videoNavigationEnabled.value = false;
      addTearDown(() {
        IOSNativeTabBar.backButtonVisible.value = false;
        IOSNativeTabBar.videoNavigationEnabled.value = false;
      });
      await tester.pumpWidget(
        NativeBackScope(
          child: NativeVideoNavigationScope(
            child: MaterialApp(navigatorKey: key, home: const Scaffold()),
          ),
        ),
      );
      key.currentState!.push(
        MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                if (!IOSNativeTabBar.usesNativeVideoNavigation(context) &&
                    !IOSNativeTabBar.hasNativeBack(context))
                  const Text('inline back'),
                if (!IOSNativeTabBar.usesNativeVideoNavigation(context))
                  const Text('inline home'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('inline home'), findsOneWidget);
      IOSNativeTabBar.videoNavigationEnabled.value = true;
      await tester.pumpAndSettle();
      expect(find.text('inline back'), findsNothing);
      expect(find.text('inline home'), findsNothing);
      IOSNativeTabBar.backButtonVisible.value = true;
      await tester.pumpAndSettle();
      expect(find.text('inline home'), findsNothing);
      IOSNativeTabBar.backButtonVisible.value = false;
      IOSNativeTabBar.videoNavigationEnabled.value = false;
      await tester.pumpAndSettle();
      expect(find.text('inline back'), findsOneWidget);
      expect(find.text('inline home'), findsOneWidget);
    },
  );
}
