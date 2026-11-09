import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/equipment/equipment_models.dart';
import '../../repositories/equipment/equipment_repository.dart';

part 'custodian_search_event.dart';
part 'custodian_search_state.dart';

/// Búsqueda de usuarios que pueden quedar como responsables de un equipo (máximo 20 resultados).
class CustodianSearchBloc extends Bloc<CustodianSearchEvent, CustodianSearchState> {
  CustodianSearchBloc({required this._repository}) : super(const CustodianSearchState()) {
    on<CustodianSearched>(_onSearched);
  }

  final EquipmentRepository _repository;
  String _latest = '';

  /// Los eventos se procesan en cola: se anota ya cuál es la búsqueda más reciente para que la
  /// respuesta de una anterior, que llega tarde, se descarte.
  @override
  void add(CustodianSearchEvent event) {
    if (event is CustodianSearched) _latest = event.text.trim();
    super.add(event);
  }

  Future<void> _onSearched(CustodianSearched event, Emitter<CustodianSearchState> emit) async {
    final query = event.text.trim();
    emit(CustodianSearchState(query: query, status: CustodianSearchStatus.loading, results: state.results));
    try {
      final results = await _repository.custodianCandidates(query);
      // Si mientras tanto se escribió otra cosa, esta respuesta ya no interesa.
      if (_latest != query) return;
      emit(CustodianSearchState(query: query, status: CustodianSearchStatus.success, results: results));
    } catch (error) {
      if (_latest != query) return;
      emit(CustodianSearchState(query: query, status: CustodianSearchStatus.failure, failure: toFailure(error)));
    }
  }
}
