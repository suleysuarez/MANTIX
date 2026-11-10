import '../../models/equipment/equipment_models.dart';
import '../../models/page_info.dart';
import '../paged/paged_bloc.dart';

/// Búsqueda de categorías para el formulario del equipo. El catálogo de categorías es corto y
/// ya viene cargado (`EquipmentCatalogBloc`), así que se filtra aquí y se entrega por páginas
/// con el mismo contrato que un listado del servidor: la hoja no necesita saber la diferencia.
class EquipmentTypeSearchBloc extends PagedBloc<EquipmentType> {
  EquipmentTypeSearchBloc({required this.types, this.search = '', super.pageSize});

  final List<EquipmentType> types;
  final String search;

  @override
  Future<PagedResult<EquipmentType>> fetch(int page) async {
    final term = search.trim().toLowerCase();
    final matches = [for (final type in types) if (term.isEmpty || type.name.toLowerCase().contains(term)) type];
    final totalPages = (matches.length / pageSize).ceil();
    final start = (page - 1) * pageSize;
    return PagedResult(
      items: matches.skip(start).take(pageSize).toList(),
      info: PageInfo(total: matches.length, page: page, pageSize: pageSize, totalPages: totalPages),
    );
  }
}
