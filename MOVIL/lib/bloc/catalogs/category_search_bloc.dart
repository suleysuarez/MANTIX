import '../../models/catalogs/catalog_models.dart';
import '../../models/page_info.dart';
import '../../repositories/catalogs/catalogs_repository.dart';
import '../paged/paged_bloc.dart';

/// Búsqueda de categorías de solicitud. El servidor entrega el catálogo completo (es corto y
/// no tiene búsqueda ni páginas), así que se pide una sola vez, se filtra aquí y se reparte
/// por páginas con el mismo contrato que un listado del servidor.
class CategorySearchBloc extends PagedBloc<RequestCategory> {
  CategorySearchBloc({required this._repository, this.search = '', super.pageSize});

  final CatalogsRepository _repository;
  final String search;
  List<RequestCategory>? _all;

  @override
  Future<PagedResult<RequestCategory>> fetch(int page) async {
    final all = _all ??= await _repository.categories();
    final term = search.trim().toLowerCase();
    final matches = [for (final category in all) if (term.isEmpty || category.name.toLowerCase().contains(term)) category];
    final start = (page - 1) * pageSize;
    return PagedResult(
      items: matches.skip(start).take(pageSize).toList(),
      info: PageInfo(total: matches.length, page: page, pageSize: pageSize, totalPages: (matches.length / pageSize).ceil()),
    );
  }
}
