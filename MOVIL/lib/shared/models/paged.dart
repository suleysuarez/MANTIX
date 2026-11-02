import '../../core/network/pagination_headers.dart';

/// One page of a listing: the records from the body plus the totals from the headers.
class Paged<T> {
  const Paged({required this.items, required this.info});

  final List<T> items;
  final PageInfo info;

  int get total => info.total;
  bool get hasMore => info.hasMore;

  Paged<R> map<R>(R Function(T item) convert) =>
      Paged(items: items.map(convert).toList(growable: false), info: info);
}
