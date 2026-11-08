import 'dart:io';

import 'package:PiliPlus/common/widgets/home_tools_slot.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/utils/ios/native_page_actions.dart';
import 'package:PiliPlus/utils/ios/native_tab_bar.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('interactive back never reveals a fallback home search row', (
    tester,
  ) async {
    final available = HomeToolsAvailability()..acknowledgeVisibility(true);
    final placement = ValueNotifier(HomeToolsPlacement.rightRail);
    final key = GlobalKey<NavigatorState>();
    addTearDown(available.dispose);
    addTearDown(placement.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        home: Scaffold(
          body: HomeTopTools(
            placement: placement,
            child: const Text('fallback search'),
          ),
        ),
      ),
    );
    for (final complete in [false, true]) {
      key.currentState!.push(
        CupertinoPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('detail')),
        ),
      );
      await tester.pumpAndSettle();
      available.acknowledgeVisibility(false);
      placement.value = resolveHomeToolsPlacement(
        useBottomNav: true,
        nativeToolsAvailable: available.value,
      );
      final gesture = await tester.startGesture(const Offset(1, 200));
      await gesture.moveBy(Offset(complete ? 650 : 180, 0));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('fallback search', skipOffstage: false), findsNothing);
      if (!complete) await gesture.moveBy(const Offset(-180, 0));
      await tester.pump(const Duration(milliseconds: 350));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('fallback search', skipOffstage: false), findsNothing);
      expect(find.text('detail'), complete ? findsNothing : findsOneWidget);
      if (!complete) {
        key.currentState!.pop();
        await tester.pumpAndSettle();
      }
      available.acknowledgeVisibility(true);
    }
  });
  testWidgets(
    'home keeps its search row absent while covered and gap is halved',
    (tester) async {
      final available = HomeToolsAvailability()..acknowledgeVisibility(true);
      final placement = ValueNotifier(HomeToolsPlacement.rightRail);
      addTearDown(available.dispose);
      addTearDown(placement.dispose);
      final home = ValueListenableBuilder(
        valueListenable: placement,
        builder: (_, value, child) => Padding(
          padding: EdgeInsets.only(top: homeTopSpacing(24, value)),
          child: Column(
            children: [
              HomeTopTools(
                placement: placement,
                child: const SizedBox(height: 50, child: Text('搜索')),
              ),
              Padding(
                padding: EdgeInsets.only(top: homeTopSpacing(4, value)),
                child: const Text('分区', key: Key('tabs')),
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(
        Directionality(textDirection: TextDirection.ltr, child: home),
      );
      final initial = tester.getTopLeft(find.byKey(const Key('tabs')));
      expect(initial.dy, 14); // Previous top inset + tab gap was 24 + 4.
      for (final shown in [false, true, false, true]) {
        available.acknowledgeVisibility(shown);
        placement.value = resolveHomeToolsPlacement(
          useBottomNav: true,
          nativeToolsAvailable: available.value,
        );
        await tester.pump();
        expect(find.text('搜索'), findsNothing);
        expect(tester.getTopLeft(find.byKey(const Key('tabs'))), initial);
      }
    },
  );
  testWidgets('kept-alive home reacts to sidebar handoff and native failure', (
    tester,
  ) async {
    final placement = ValueNotifier(HomeToolsPlacement.sideBar);
    addTearDown(placement.dispose);
    // Reuse this exact widget instance: the old plain bool left HomePage stale.
    final home = HomeTopTools(
      placement: placement,
      child: const Text('搜索', key: Key('search')),
    );
    await tester.pumpWidget(
      Directionality(textDirection: TextDirection.ltr, child: home),
    );
    expect(find.byKey(const Key('search')), findsNothing);
    placement.value = resolveHomeToolsPlacement(
      useBottomNav: true,
      nativeToolsAvailable: false,
    );
    await tester.pump();
    expect(find.byKey(const Key('search')), findsOneWidget);
    placement.value = resolveHomeToolsPlacement(
      useBottomNav: true,
      nativeToolsAvailable: true,
    );
    await tester.pump();
    expect(find.byKey(const Key('search')), findsNothing);
    placement.value = resolveHomeToolsPlacement(
      useBottomNav: true,
      nativeToolsAvailable: false,
    );
    await tester.pump();
    expect(find.byKey(const Key('search')), findsOneWidget);
  });

  test('root tools and account badges cannot leak into a detail or popup', () async {
    late Map<String, Object> state;
    final registry = NativePageActionRegistry(
      onChanged: (value) => state = value,
    );
    final root = Object(), detail = Object(), popup = Object();
    final calls = <String>[];
    void home({String? badge}) => registry.register(
      page: root,
      homeTools: true,
      actions: [
        const NativePageAction(id: 'search', title: '搜索'),
        NativePageAction(id: 'notifications', title: '消息', badge: badge),
      ],
      handler: calls.add,
    );
    registry.setTopPage(root);
    home(badge: '12');
    final owner = state['owner'] as int;
    expect(state['homeTools'], true);
    final items = state['items'] as List;
    expect(items[1], containsPair('badge', '12'));
    expect(items.length, 2);
    expect(items.map((item) => (item as Map)['id']), [
      'search',
      'notifications',
    ]);
    await registry.handle(owner: owner, id: 'search');
    expect(calls, ['search']);
    registry.setTopPage(detail);
    expect(state['homeTools'], false);
    await registry.handle(owner: owner, id: 'avatar');
    registry.setTopPage(popup);
    await registry.handle(owner: owner, id: 'notifications');
    expect(calls, ['search']);
    // Account changes can update the covered root without replacing detail UI.
    home();
    expect(state['items'], isEmpty);
    registry.setTopPage(root);
    expect(state['homeTools'], true);
    expect((state['items'] as List)[1], isNot(contains('badge')));
    await registry.handle(owner: owner, id: 'avatar');
    expect(calls, ['search']);
    await registry.handle(owner: owner, id: 'notifications');
    expect(calls.last, 'notifications');
    registry.unregister(root);
    expect(state['homeTools'], false);
  });

  group('sidebar conflict prevention', () {
    late Directory directory;
    setUpAll(() async {
      directory = await Directory.systemTemp.createTemp('piliplus-home-tools-');
      Hive.init(directory.path);
      GStorage.setting = await Hive.openBox('setting');
    });
    tearDownAll(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    testWidgets(
      'detected rail disables both switch and tile, ignoring saved true',
      (tester) async {
        await tester.runAsync(
          () => GStorage.setting.put(SettingBoxKey.useSideBar, true),
        );
        IOSNativeTabBar.rightRailDevice.value = false;
        addTearDown(() => IOSNativeTabBar.rightRailDevice.value = false);
        final model = SwitchModel(
          title: '改用侧边栏',
          setKey: SettingBoxKey.useSideBar,
          disabledWhen: IOSNativeTabBar.rightRailDevice,
          disabledSubtitle: '此机型使用系统右侧竖栏，已停用此选项',
        );
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: model.widget)),
        );
        expect(Pref.useSideBar, true);
        expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
        IOSNativeTabBar.rightRailDevice.value = true;
        await tester.pumpAndSettle();
        final disabled = tester.widget<Switch>(find.byType(Switch));
        expect(disabled.value, false);
        expect(disabled.onChanged, isNull);
        expect(Pref.useSideBar, false);
        expect(find.text(model.disabledSubtitle!), findsOneWidget);
        await tester.tap(find.text('改用侧边栏'));
        await tester.pumpAndSettle();
        expect(Pref.useSideBar, false);
        // Other devices retain the user's existing preference.
        IOSNativeTabBar.rightRailDevice.value = false;
        await tester.pumpAndSettle();
        expect(Pref.useSideBar, true);
        expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
      },
    );
  });
}
