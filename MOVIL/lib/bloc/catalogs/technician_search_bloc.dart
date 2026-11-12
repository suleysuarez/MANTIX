import '../../models/page_info.dart';
import '../../models/technicians/technician_models.dart';
import '../../repositories/technicians/technicians_repository.dart';
import '../paged/paged_bloc.dart';

/// Técnicos que se pueden asignar a un ticket, por páginas y con búsqueda en el servidor.
/// Solo se ofrecen los de cuenta activa: se pide `is_active=true` y, por si el servidor aún no
/// tiene ese filtro, los inactivos que lleguen se descartan aquí.
class TechnicianSearchBloc extends PagedBloc<Technician> {
  TechnicianSearchBloc({required this._repository, this.search = '', super.pageSize});

  final TechniciansRepository _repository;
  final String search;

  @override
  Future<PagedResult<Technician>> fetch(int page) async {
    final result = await _repository.list(search: search, page: page, size: pageSize, isActive: true);
    return PagedResult(items: [for (final technician in result.items) if (technician.isActive) technician], info: result.info);
  }
}
