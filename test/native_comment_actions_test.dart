import 'package:PiliPlus/utils/ios/native_comment_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('comment belongs to the current route and the visible panel', () async {
    final states = <Map<String, Object>>[];
    final calls = <String>[];
    var allowed = true;
    var firstVisible = true;
    var secondVisible = false;
    final firstPage = Object(), secondPage = Object();
    final source = Object();
    final registry = NativeCommentActions(
      canPresent: () => allowed,
      onChanged: states.add,
    );
    registry.setTopPage(firstPage);
    final first = registry.register(
      source: source,
      page: firstPage,
      isVisible: () => firstVisible,
      onPressed: () {
        calls.add('first');
      },
    );
    final second = registry.register(
      source: Object(),
      page: firstPage,
      isVisible: () => secondVisible,
      onPressed: () {
        calls.add('second');
      },
    );
    final other = registry.register(
      source: Object(),
      page: secondPage,
      isVisible: () => true,
      onPressed: () {
        calls.add('other');
      },
    );
    expect(states.last['owner'], first);
    firstVisible = false;
    secondVisible = true;
    registry.refresh();
    expect(states.last['owner'], second);
    await registry.handle(first);
    await registry.handle(second);
    expect(calls, ['second']);
    registry.setTopPage(secondPage);
    await registry.handle(second);
    await registry.handle(other);
    expect(calls, ['second', 'other']);
    allowed = false;
    await registry.handle(other);
    expect(states.last['visible'], false);
    expect(calls.length, 2);
    allowed = true;
    registry.setTopPage(firstPage);
    secondVisible = false;
    firstVisible = true;
    registry.refresh();
    expect(states.last['owner'], first);
    registry.unregister(source);
    expect(states.last['visible'], false);
  });

  test('rebuilding retains owner; moving the same source to a new route invalidates old taps', () async {
    final states = <Map<String, Object>>[];
    final registry = NativeCommentActions(
      canPresent: () => true,
      onChanged: states.add,
    );
    final page = Object(), next = Object(), source = Object();
    var calls = 0;
    int register(Object route) => registry.register(
      source: source,
      page: route,
      isVisible: () => true,
      onPressed: () {
        calls++;
      },
    );
    registry.setTopPage(page);
    final owner = register(page);
    expect(register(page), owner);
    expect(states.length, 1);
    final nextOwner = register(next);
    expect(nextOwner, isNot(owner));
    registry.setTopPage(next);
    await registry.handle(owner);
    expect(calls, 0);
    await registry.handle(nextOwner);
    expect(calls, 1);
    registry.unregister(source);
    await registry.handle(nextOwner);
    expect(calls, 1);
  });
}
