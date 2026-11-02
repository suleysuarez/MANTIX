import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/network/pagination_headers.dart';

PageInfo read(Map<String, List<String>> headers, {int items = 20}) =>
    PageInfo.fromHeaders(
      headers,
      itemCount: items,
      requestedPage: 1,
      requestedSize: 20,
    );

void main() {
  test('reads the four headers', () {
    final info = read({
      'x-total-count': ['45'],
      'x-page': ['2'],
      'x-page-size': ['20'],
      'x-total-pages': ['3'],
    });
    expect(info.total, 45);
    expect(info.page, 2);
    expect(info.pageSize, 20);
    expect(info.totalPages, 3);
    expect(info.hasMore, isTrue);
  });

  test('is case-insensitive', () {
    final info = read({
      'X-Total-Count': ['5'],
      'X-Page': ['1'],
      'X-Total-Pages': ['1'],
    });
    expect(info.total, 5);
    expect(info.hasMore, isFalse);
  });

  test('the last page has no more', () {
    final info = read({
      'x-total-count': ['45'],
      'x-page': ['3'],
      'x-page-size': ['20'],
      'x-total-pages': ['3'],
    });
    expect(info.hasMore, isFalse);
  });

  test('missing total: single page with the received records', () {
    final info = read({}, items: 7);
    expect(info.total, 7);
    expect(info.totalPages, 1);
    expect(info.hasMore, isFalse);
  });

  test('invalid or negative values count as missing', () {
    expect(
      read({
        'x-total-count': ['abc'],
      }, items: 3).total,
      3,
    );
    expect(
      read({
        'x-total-count': ['-4'],
      }, items: 3).total,
      3,
    );
  });

  test('empty listing', () {
    final info = read({
      'x-total-count': ['0'],
    }, items: 0);
    expect(info.total, 0);
    expect(info.totalPages, 0);
    expect(info.hasMore, isFalse);
  });
}
