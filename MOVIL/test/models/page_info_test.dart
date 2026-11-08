import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/models/page_info.dart';

Headers headers(Map<String, String> values) => Headers.fromMap({for (final e in values.entries) e.key: [e.value]});

void main() {
  const complete = {'x-total-count': '45', 'x-page': '2', 'x-page-size': '20', 'x-total-pages': '3'};

  test('lee las cuatro cabeceras de paginación', () {
    final info = PageInfo.fromHeaders(headers(complete))!;
    expect(info.total, 45);
    expect(info.page, 2);
    expect(info.pageSize, 20);
    expect(info.totalPages, 3);
  });

  test('las cabeceras no distinguen mayúsculas', () {
    final info = PageInfo.fromHeaders(headers({
      'X-Total-Count': '5',
      'X-Page': '1',
      'X-Page-Size': '20',
      'X-Total-Pages': '1',
    }));
    expect(info?.total, 5);
  });

  test('hasNext y nextPage', () {
    expect(PageInfo.fromHeaders(headers(complete))!.nextPage, 3);
    final last = PageInfo.fromHeaders(headers({...complete, 'x-page': '3'}))!;
    expect(last.hasNext, isFalse);
    expect(last.nextPage, isNull);
  });

  test('sin resultados: cero páginas y sin siguiente', () {
    final empty = PageInfo.fromHeaders(headers({'x-total-count': '0', 'x-page': '1', 'x-page-size': '20', 'x-total-pages': '0'}))!;
    expect(empty.hasNext, isFalse);
  });

  test('si falta una cabecera devuelve null en vez de fallar', () {
    for (final missing in complete.keys) {
      final partial = {...complete}..remove(missing);
      expect(PageInfo.fromHeaders(headers(partial)), isNull, reason: 'sin $missing');
    }
  });

  test('valores no numéricos o fuera de rango devuelven null', () {
    expect(PageInfo.fromHeaders(headers({...complete, 'x-page': 'dos'})), isNull);
    expect(PageInfo.fromHeaders(headers({...complete, 'x-page': '0'})), isNull);
    expect(PageInfo.fromHeaders(headers({...complete, 'x-page-size': '0'})), isNull);
    expect(PageInfo.fromHeaders(headers({...complete, 'x-total-count': '-1'})), isNull);
  });

  test('PagedResult sin información se trata como una sola página', () {
    const result = PagedResult<int>(items: [1, 2]);
    expect(result.hasNext, isFalse);
  });

  test('el tamaño de página por defecto es el del plan', () {
    expect(PageInfo.defaultPageSize, 20);
  });
}
