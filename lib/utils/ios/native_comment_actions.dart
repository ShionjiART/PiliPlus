import 'dart:async';

class _CommentAction {
  _CommentAction(
    this.owner,
    this.page,
    this.isVisible,
    this.onPressed,
    this.label,
  );
  final int owner;
  final Object page;
  final bool Function() isVisible;
  final FutureOr<void> Function() onPressed;
  final String label;
}

/// A separate route-owned slot lets a nested comment panel coexist with the
/// video's back/home/fullscreen commands instead of replacing them.
class NativeCommentActions {
  NativeCommentActions({required this.canPresent, required this.onChanged});
  final bool Function() canPresent;
  final void Function(Map<String, Object> state) onChanged;
  final _actions = <Object, _CommentAction>{};
  Object? _page;
  int _nextOwner = 0;
  int _activeOwner = 0;
  String _label = '';
  bool get hasCandidates => _actions.isNotEmpty;

  int register({
    required Object source,
    required Object page,
    required bool Function() isVisible,
    required FutureOr<void> Function() onPressed,
    String label = '发表评论',
  }) {
    final old = _actions[source];
    final owner = old?.page == page ? old!.owner : ++_nextOwner;
    _actions[source] = _CommentAction(owner, page, isVisible, onPressed, label);
    refresh();
    return owner;
  }

  void unregister(Object source) {
    _actions.remove(source);
    refresh();
  }

  void setTopPage(Object? page) {
    _page = page;
    refresh();
  }

  void refresh() {
    _CommentAction? selected;
    if (canPresent()) {
      for (final action in _actions.values) {
        if (action.page == _page && action.isVisible()) selected = action;
      }
    }
    final owner = selected?.owner ?? 0;
    final label = selected?.label ?? '';
    if (owner == _activeOwner && label == _label) return;
    _activeOwner = owner;
    _label = label;
    onChanged({'owner': owner, 'visible': owner != 0, 'label': label});
  }

  Future<void> handle(int owner) async {
    refresh();
    if (owner == 0 || owner != _activeOwner) return;
    for (final action in _actions.values) {
      if (action.owner == owner) {
        await action.onPressed();
        return;
      }
    }
  }
}
