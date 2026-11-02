/// The page described by the `X-Total-Count`, `X-Page`, `X-Page-Size` and `X-Total-Pages`
/// response headers of every listing.
class PageInfo {
  const PageInfo({
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  final int total;
  final int page;
  final int pageSize;
  final int totalPages;

  bool get hasMore => page < totalPages;

  /// [headers] may use any letter case (Dio lowercases them). If the total is missing or not a
  /// number the response is treated as a single page holding [itemCount] records.
  factory PageInfo.fromHeaders(
    Map<String, List<String>> headers, {
    required int itemCount,
    required int requestedPage,
    required int requestedSize,
  }) {
    int? read(String name) {
      for (final entry in headers.entries) {
        if (entry.key.toLowerCase() == name && entry.value.isNotEmpty) {
          final value = int.tryParse(entry.value.first.trim());
          return value != null && value >= 0 ? value : null;
        }
      }
      return null;
    }

    final total = read('x-total-count');
    if (total == null) {
      return PageInfo(
        total: itemCount,
        page: requestedPage,
        pageSize: requestedSize,
        totalPages: 1,
      );
    }
    return PageInfo(
      total: total,
      page: read('x-page') ?? requestedPage,
      pageSize: read('x-page-size') ?? requestedSize,
      totalPages: read('x-total-pages') ?? (total == 0 ? 0 : 1),
    );
  }
}
