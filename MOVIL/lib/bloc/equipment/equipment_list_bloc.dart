import 'dart:async';

import '../../models/equipment/equipment_models.dart';
import '../../models/page_info.dart';
import '../../repositories/equipment/equipment_repository.dart';
import '../paged/paged_bloc.dart';

/// Catálogo de equipos. [statuses] es el filtro de estado (lista separada por comas, ver
/// `EquipmentGroup.filter`; `null`: todos) y [search] el texto buscado. Cambiar un filtro
/// crea un Bloc nuevo (la pantalla le pone una `key`), igual que «Mis solicitudes».
class EquipmentListBloc extends PagedBloc<Equipment> {
  EquipmentListBloc({required this._repository, this.statuses, this.search = ''}) {
    _changes = _repository.changes.listen((_) => add(const PagedRefreshed()));
  }

  final EquipmentRepository _repository;
  final String? statuses;
  final String search;
  late final StreamSubscription<void> _changes;

  @override
  Future<PagedResult<Equipment>> fetch(int page) => _repository.listEquipment(page: page, statuses: statuses, search: search);

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
