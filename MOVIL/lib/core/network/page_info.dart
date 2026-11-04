import 'package:dio/dio.dart';

/// Paginación que el backend devuelve en cabeceras (`X-Total-Count`, `X-Page`,
/// `X-Page-Size`, `X-Total-Pages`). El cuerpo es un array JSON plano.
class PageInfo {
  const PageInfo({required this.total, required this.page, required this.pageSize, required this.totalPages});

  /// Tamaño de página que envía la app (docs/flutter-plan.md).
  static const int defaultPageSize = 20;

  final int total;

  /// Base 1.
  final int page;
  final int pageSize;
  final int totalPages;

  bool get hasNext => page < totalPages;

  /// Siguiente página a pedir, o `null` si ya no hay más.
  int? get nextPage => hasNext ? page + 1 : null;

  /// Lee las cabeceras. Si falta alguna devuelve `null`: la pantalla trata la
  /// respuesta como una sola página en vez de fallar.
  static PageInfo? fromHeaders(Headers headers) {
    int? read(String name) => int.tryParse(headers.value(name) ?? '');
    final total = read('x-total-count');
    final page = read('x-page');
    final pageSize = read('x-page-size');
    final totalPages = read('x-total-pages');
    if (total == null || page == null || pageSize == null || totalPages == null) return null;
    if (page < 1 || pageSize < 1 || totalPages < 0 || total < 0) return null;
    return PageInfo(total: total, page: page, pageSize: pageSize, totalPages: totalPages);
  }
}

/// Una página de resultados con su información de paginación.
class PagedResult<T> {
  const PagedResult({required this.items, this.info});

  final List<T> items;

  /// `null` cuando el backend no envió las cabeceras.
  final PageInfo? info;

  bool get hasNext => info?.hasNext ?? false;
}
