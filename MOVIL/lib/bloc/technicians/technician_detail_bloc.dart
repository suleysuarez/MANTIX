import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/requests/request_models.dart';
import '../../models/technicians/technician_models.dart';
import '../../repositories/requests/requests_repository.dart';
import '../../repositories/technicians/technicians_repository.dart';

part 'technician_detail_event.dart';
part 'technician_detail_state.dart';

/// Lo que la ficha de un técnico pide aparte de la lista: sus indicadores del periodo y sus
/// tickets abiertos. Cada bloque carga y falla por separado.
class TechnicianDetailBloc extends Bloc<TechnicianDetailEvent, TechnicianDetailState> {
  TechnicianDetailBloc({required this._technicians, required this._requests, required this.technicianId, this.withTickets = true}) : super(const TechnicianDetailState()) {
    on<TechnicianDetailRequested>(_onRequested);
    on<TechnicianPerformanceRetried>((_, emit) => _loadPerformance(emit));
    on<TechnicianTicketsRetried>((_, emit) => _loadTickets(emit));
  }

  /// Estados en los que un ticket cuenta como abierto: los mismos que usa el servidor para
  /// `open_tickets`.
  static const openStatuses = 'submitted,triaged,assigned,in_progress,waiting';

  /// Cuántos tickets abiertos se listan; el total sale de las cabeceras.
  static const ticketsShown = 10;

  final TechniciansRepository _technicians;
  final RequestsRepository _requests;
  final int technicianId;

  /// `false` para quien no puede ver tickets: ese bloque ni se pide.
  final bool withTickets;

  Future<void> _onRequested(TechnicianDetailRequested event, Emitter<TechnicianDetailState> emit) => Future.wait([_loadPerformance(emit), if (withTickets) _loadTickets(emit)]);

  Future<void> _loadPerformance(Emitter<TechnicianDetailState> emit) async {
    emit(state.copyWith(performanceStatus: DetailBlockStatus.loading));
    try {
      final report = await _technicians.performance();
      // Sin fila propia (por ejemplo, el servidor solo deja ver la de quien llama) no hay dato.
      emit(state.copyWith(performanceStatus: DetailBlockStatus.ready, performance: report.byTechnician[technicianId], period: report.period));
    } catch (error) {
      emit(state.copyWith(performanceStatus: DetailBlockStatus.failure, performanceFailure: toFailure(error)));
    }
  }

  Future<void> _loadTickets(Emitter<TechnicianDetailState> emit) async {
    emit(state.copyWith(ticketsStatus: DetailBlockStatus.loading));
    try {
      final result = await _requests.listRequests(technicianIds: [technicianId], status: openStatuses, size: ticketsShown);
      emit(state.copyWith(ticketsStatus: DetailBlockStatus.ready, tickets: result.items, ticketsTotal: result.info?.total ?? result.items.length));
    } catch (error) {
      emit(state.copyWith(ticketsStatus: DetailBlockStatus.failure, ticketsFailure: toFailure(error)));
    }
  }
}
