import 'dart:async';

/// A button a page shows in the native vertical bar (iPhone Duo).
class NativePageAction {
  const NativePageAction({
    required this.id,
    required this.title,
    this.count,
    this.selected = false,
    this.selectedColor,
    this.enabled = true,
    this.standalone = false,
  });

  final String id;
  final String title;

  /// Short text shown under the icon, such as a like count.
  final String? count;
  final bool selected;

  /// ARGB color of a selected button, such as the app's theme color for a
  /// like; the system tint when null.
  final int? selectedColor;
  final bool enabled;

  /// Shown as its own button rather than grouped with its neighbours.
  final bool standalone;

  Map<String, Object> toMap() => {
    'id': id,
    'title': title,
    'count': ?count,
    'selected': selected,
    'selectedColor': ?selectedColor,
    'enabled': enabled,
    if (standalone) 'standalone': true,
  };
}

typedef NativePageActionHandler = FutureOr<void> Function(String id);

class _PageActions {
  _PageActions(this.token, this.actions, this.handler);

  final int token;
  final List<NativePageAction> actions;
  final NativePageActionHandler handler;
}

/// Keeps each page's buttons attached to that page, including when pages are
/// stacked, and publishes the buttons of the top page.
///
/// Each page gets an owner token. The native side sends it back with a tap, so
/// a tap queued for a page that is no longer on top is ignored.
class NativePageActionRegistry {
  NativePageActionRegistry({required this.onChanged});

  final void Function(Map<String, Object> state) onChanged;
  final Map<Object, _PageActions> _pages = {};
  Object? _topPage;
  int _nextToken = 0;

  void setTopPage(Object? page) {
    _topPage = page;
    _publish();
  }

  void register({
    required Object page,
    required List<NativePageAction> actions,
    required NativePageActionHandler handler,
  }) {
    final token = _pages[page]?.token ?? ++_nextToken;
    _pages[page] = _PageActions(token, List.unmodifiable(actions), handler);
    if (page == _topPage) _publish();
  }

  void unregister(Object page) {
    if (_pages.remove(page) != null && page == _topPage) _publish();
  }

  void _publish() {
    final page = _pages[_topPage];
    onChanged({
      'owner': page?.token ?? 0,
      'items': [
        for (final action in page?.actions ?? const <NativePageAction>[])
          action.toMap(),
      ],
    });
  }

  Future<void> handle({required int owner, required String id}) async {
    final page = _pages[_topPage];
    if (page == null || page.token != owner) return;
    if (!page.actions.any((action) => action.id == id && action.enabled)) {
      return;
    }
    await page.handler(id);
  }
}
