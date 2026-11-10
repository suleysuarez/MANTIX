import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/requests/request_models.dart';
import '../../repositories/equipment/equipment_repository.dart';
import '../../repositories/requests/requests_repository.dart';

part 'equipment_detail_event.dart';
part 'equipment_detail_state.dart';

/// Historial de tickets y adjuntos de un equipo, para su ficha en la hoja inferior.
class EquipmentDetailBloc extends Bloc<EquipmentDetailEvent, EquipmentDetailState> {
  EquipmentDetailBloc({required this.equipmentId, required this._equipment, required this._requests}) : super(const EquipmentDetailState()) {
    on<EquipmentDetailStarted>(_onStarted);
  }

  /// Tickets que se piden del historial; los más recientes primero.
  static const ticketLimit = 10;

  final int equipmentId;
  final EquipmentRepository _equipment;
  final RequestsRepository _requests;

  Future<void> _onStarted(EquipmentDetailStarted event, Emitter<EquipmentDetailState> emit) async {
    emit(state.copyWith(ticketsStatus: DetailPart.loading, attachmentsStatus: DetailPart.loading));
    await Future.wait([_loadTickets(emit), _loadAttachments(emit)]);
  }

  Future<void> _loadTickets(Emitter<EquipmentDetailState> emit) async {
    try {
      final result = await _requests.listRequests(equipmentId: equipmentId, size: ticketLimit);
      emit(state.copyWith(tickets: result.items, ticketsStatus: DetailPart.success));
    } catch (error) {
      emit(state.copyWith(ticketsStatus: DetailPart.failure, ticketsFailure: toFailure(error)));
    }
  }

  Future<void> _loadAttachments(Emitter<EquipmentDetailState> emit) async {
    try {
      // Primero se espera y después se lee `state`: leerlo antes pisaría lo que la otra carga emitió.
      final list = await _equipment.listAttachments(equipmentId);
      emit(state.copyWith(attachments: list, attachmentsStatus: DetailPart.success));
    } catch (error) {
      emit(state.copyWith(attachmentsStatus: DetailPart.failure, attachmentsFailure: toFailure(error)));
    }
  }
}
