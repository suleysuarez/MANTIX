import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../core/format/technicians_format.dart';
import '../../models/page_info.dart';
import '../../models/technicians/technician_filters.dart';
import '../../models/technicians/technician_models.dart';
import '../../repositories/technicians/technicians_repository.dart';

part 'technicians_list_event.dart';
part 'technicians_list_state.dart';

/// Lista de técnicos con su carga. Trae el catálogo completo y la carga a la vez y filtra,
/// ordena y pagina en la app, porque el servidor no ordena ni filtra por carga. Los dos bloques
/// fallan por separado: sin la carga, la lista sigue y los indicadores dicen «no disponible».
/// Se recarga sola cuando alguien registra o edita un técnico.
class TechniciansListBloc extends Bloc<TechniciansListEvent, TechniciansListState> {
  TechniciansListBloc({required this._repository}) : super(const TechniciansListState()) {
    on<TechniciansRequested>(_onRequested);
    on<TechniciansSearchChanged>((event, emit) => emit(state.copyWith(filters: state.filters.copyWith(search: event.search), page: 1, clearPinned: true)));
    on<TechniciansFiltersChanged>((event, emit) => emit(state.copyWith(filters: event.filters, page: 1, clearPinned: true)));
    on<TechniciansOrderChanged>((event, emit) => emit(state.copyWith(order: event.order, page: 1, clearPinned: true)));
    on<TechniciansPageChanged>((event, emit) => emit(state.copyWith(page: event.page.clamp(1, state.totalPages))));
    on<TechniciansPageSizeChanged>((event, emit) => emit(state.copyWith(pageSize: event.pageSize, page: 1)));
    on<TechnicianCreatedShown>(_onCreated);
    _changes = _repository.changes.listen((_) => add(const TechniciansRequested()));
  }

  final TechniciansRepository _repository;
  late final StreamSubscription<void> _changes;

  Future<void> _onRequested(TechniciansRequested event, Emitter<TechniciansListState> emit) async {
    // Al recargar se conserva lo que ya se ve; solo cambia lo que llega.
    emit(state.copyWith(status: TechniciansStatus.loading, clearFailure: true));
    try {
      // La carga nunca tumba la lista: su error se guarda aparte.
      final workload = _repository.workload().then<(Workload?, Failure?)>((value) => (value, null), onError: (Object error) => (null, toFailure(error)));
      final technicians = await _repository.all();
      final (loads, loadFailure) = await workload;
      emit(state.copyWith(
        status: TechniciansStatus.ready,
        technicians: technicians,
        workload: loads,
        clearWorkload: loads == null,
        workloadFailure: loadFailure,
        clearWorkloadFailure: loadFailure == null,
      ));
      // Si la lista se acortó, la página actual puede haber dejado de existir.
      if (state.page > state.totalPages) emit(state.copyWith(page: state.totalPages));
    } catch (error) {
      emit(state.copyWith(status: TechniciansStatus.failure, failure: toFailure(error)));
    } finally {
      event.done?.complete();
    }
  }

  /// Un técnico recién registrado: sin filtros, en la página 1 y de primero. La lista se recarga
  /// sola por el aviso del repositorio; aquí se añade ya para que se vea sin esperar.
  void _onCreated(TechnicianCreatedShown event, Emitter<TechniciansListState> emit) {
    final known = state.technicians.any((technician) => technician.id == event.technician.id);
    emit(state.copyWith(
      technicians: known ? null : [...state.technicians, event.technician],
      filters: const TechnicianFilters(),
      page: 1,
      pinnedId: event.technician.id,
    ));
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
