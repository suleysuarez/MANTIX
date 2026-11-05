import '../../../../core/network/page_info.dart';
import '../../../../core/network/paged/paged_bloc.dart';
import '../../data/models.dart';
import '../../data/requests_repository.dart';

/// Resultados del selector de equipo; [search] es el texto buscado.
class EquipmentSearchBloc extends PagedBloc<EquipmentOption> {
  EquipmentSearchBloc({required this._repository, this.search = ''});

  final RequestsRepository _repository;
  final String search;

  @override
  Future<PagedResult<EquipmentOption>> fetch(int page) => _repository.searchEquipment(search: search, page: page);
}
