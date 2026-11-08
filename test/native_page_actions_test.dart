import 'package:PiliPlus/utils/ios/native_page_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const like = NativePageAction(id: 'like', title: '点赞', count: '428');
  test(
    'commands stay with their route across modals and stacked details',
    () async {
      late Map<String, Object> state;
      final registry = NativePageActionRegistry(
        onChanged: (value) => state = value,
      );
      final first = Object();
      final second = Object();
      final modal = Object();
      final called = <String>[];
      registry
        ..setTopPage(first)
        ..register(
          page: first,
          actions: [like],
          handler: (id) => called.add('first:$id'),
        );
      final firstOwner = state['owner'] as int;
      registry.register(
        page: second,
        actions: [like],
        handler: (id) => called.add('second:$id'),
      );
      expect(state['owner'], firstOwner);
      registry.setTopPage(second);
      final secondOwner = state['owner'] as int;
      await registry.handle(owner: firstOwner, id: 'like');
      expect(called, isEmpty);
      await registry.handle(owner: secondOwner, id: 'like');
      expect(called, ['second:like']);
      registry.setTopPage(modal);
      expect(state['items'], isEmpty);
      await registry.handle(owner: secondOwner, id: 'like');
      expect(called.length, 1);
      registry.setTopPage(first);
      expect(state['owner'], firstOwner);
      await registry.handle(owner: firstOwner, id: 'like');
      expect(called.last, 'first:like');
    },
  );

  test(
    'updates keep owner stable; disabled and removed actions cannot dispatch',
    () async {
      late Map<String, Object> state;
      final registry = NativePageActionRegistry(
        onChanged: (value) => state = value,
      );
      final page = Object();
      final called = <String>[];
      registry
        ..setTopPage(page)
        ..register(page: page, actions: [like], handler: called.add);
      final owner = state['owner'] as int;
      registry.register(
        page: page,
        actions: [
          const NativePageAction(
            id: 'like',
            title: '点赞',
            count: '429',
            selected: true,
          ),
          const NativePageAction(id: 'compose', title: '写评论', enabled: false),
        ],
        handler: called.add,
      );
      expect(state['owner'], owner);
      expect((state['items'] as List).first, containsPair('selected', true));
      await registry.handle(owner: owner, id: 'compose');
      await registry.handle(owner: owner, id: 'unknown');
      expect(called, isEmpty);
      registry.unregister(page);
      expect(state['items'], isEmpty);
      await registry.handle(owner: owner, id: 'like');
      expect(called, isEmpty);
      registry.register(page: page, actions: [like], handler: called.add);
      expect(state['owner'], isNot(owner));
      await registry.handle(owner: owner, id: 'like');
      expect(called, isEmpty);
    },
  );
}
