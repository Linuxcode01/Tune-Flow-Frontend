/// Mirrors the backend's `PageResponse` envelope (content/page/size/totalElements/...).
///
/// Every list endpoint in the API returns this shape, so the client has exactly one pagination
/// parser (docs section 10).
class PagedResponse<T> {
  const PagedResponse({
    required this.items,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
    required this.isFirst,
    required this.isLast,
  });

  /// Parses `{content, page, size, totalElements, totalPages, first, last, empty}`.
  factory PagedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic> json) itemMapper,
  ) {
    final List<dynamic> rawItems = (json['content'] as List<dynamic>?) ?? const <dynamic>[];
    final int page = (json['page'] as num?)?.toInt() ?? 0;
    final int size = (json['size'] as num?)?.toInt() ?? rawItems.length;
    final int totalElements = (json['totalElements'] as num?)?.toInt() ?? rawItems.length;
    final int totalPages = (json['totalPages'] as num?)?.toInt() ?? 1;

    return PagedResponse<T>(
      items: rawItems.whereType<Map<String, dynamic>>().map(itemMapper).toList(growable: false),
      page: page,
      size: size,
      totalElements: totalElements,
      totalPages: totalPages,
      isFirst: json['first'] as bool? ?? page == 0,
      isLast: json['last'] as bool? ?? page >= totalPages - 1,
    );
  }

  /// An empty page, used as the initial state of paginated providers.
  const PagedResponse.empty()
      : items = const <Never>[],
        page = 0,
        size = 0,
        totalElements = 0,
        totalPages = 0,
        isFirst = true,
        isLast = true;

  final List<T> items;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;
  final bool isFirst;
  final bool isLast;

  bool get isEmpty => items.isEmpty;
  bool get hasMore => !isLast && items.isNotEmpty;

  /// Number of the next page, or null at the end.
  int? get nextPage => hasMore ? page + 1 : null;

  /// Returns a new page with [more] appended - how a "load more" list grows.
  PagedResponse<T> append(PagedResponse<T> more) {
    return PagedResponse<T>(
      items: <T>[...items, ...more.items],
      page: more.page,
      size: more.size,
      totalElements: more.totalElements,
      totalPages: more.totalPages,
      isFirst: page == 0 && isFirst,
      isLast: more.isLast,
    );
  }
}
