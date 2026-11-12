import '../../models/equipment/equipment_models.dart';
import '../../models/page_info.dart';
import '../../repositories/equipment/equipment_repository.dart';
import '../paged/paged_bloc.dart';

/// Equipos por páginas y con búsqueda en el servidor (etiqueta, serie, marca o modelo), para
/// elegir uno en un formulario. Cambiar el texto es crear un Bloc nuevo.
class EquipmentSearchBloc extends PagedBloc<Equipment> {
  EquipmentSearchBloc({required this._repository, this.search = '', super.pageSize});

  final EquipmentRepository _repository;
  final String search;

  @override
  Future<PagedResult<Equipment>> fetch(int page) => _repository.listEquipment(page: page, size: pageSize, search: search);
}
