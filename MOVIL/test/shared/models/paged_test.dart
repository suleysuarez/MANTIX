import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/network/pagination_headers.dart';
import 'package:mantix/shared/models/paged.dart';

void main() {
  const info = PageInfo(total: 45, page: 1, pageSize: 20, totalPages: 3);

  test('exposes the total and whether there are more pages', () {
    const page = Paged(items: [1, 2, 3], info: info);
    expect(page.total, 45);
    expect(page.hasMore, isTrue);
  });

  test('map converts the items and keeps the page info', () {
    const page = Paged(items: [1, 2, 3], info: info);
    final mapped = page.map((n) => 'n$n');
    expect(mapped.items, ['n1', 'n2', 'n3']);
    expect(mapped.info, same(info));
  });
}
