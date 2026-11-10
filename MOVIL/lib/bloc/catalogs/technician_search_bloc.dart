import '../../models/catalogs/catalog_models.dart';
import '../../models/page_info.dart';
import '../../repositories/catalogs/catalogs_repository.dart';
import '../paged/paged_bloc.dart';

/// Técnicos que se pueden asignar a un ticket, por páginas y con búsqueda en el servidor.
/// Solo se ofrecen los de cuenta activa: el servidor no tiene ese filtro, así que se descartan
/// aquí (una página puede traer menos de [pageSize]; el total sigue siendo el del servidor).
class TechnicianSearchBloc extends PagedBloc<TechnicianOption> {
  TechnicianSearchBloc({required this._repository, this.search = '', super.pageSize});

  final CatalogsRepository _repository;
  final String search;

  @override
  Future<PagedResult<TechnicianOption>> fetch(int page) async {
    final result = await _repository.technicians(search: search, page: page, size: pageSize);
    return PagedResult(items: [for (final technician in result.items) if (technician.isActive) technician], info: result.info);
  }
}
