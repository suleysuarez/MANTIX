import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/requests/request_models.dart';
import '../../repositories/requests/requests_repository.dart';

part 'request_detail_event.dart';
part 'request_detail_state.dart';

/// Detalle de una solicitud. Los adjuntos cargan aparte: si fallan, el resto del
/// detalle sigue visible.
class RequestDetailBloc extends Bloc<RequestDetailEvent, RequestDetailState> {
  RequestDetailBloc({required this._repository, required this.requestId}) : super(const RequestDetailState()) {
    on<RequestDetailRequested>(_onDetail);
    on<RequestAttachmentsRequested>(_onAttachments);
    on<RequestWorkflowRequested>(_onWorkflow);
    on<RequestStatusChangeRequested>(_onStatusChange);
  }

  final RequestsRepository _repository;
  final int requestId;

  Future<void> _onDetail(RequestDetailRequested event, Emitter<RequestDetailState> emit) async {
    // Con datos ya cargados se siguen mostrando mientras se refresca.
    if (state.ticket == null) emit(state.copyWith(status: LoadStatus.loading, clearFailure: true));
    try {
      // Se espera antes de leer `state`: el ticket y los adjuntos cargan a la vez y cada
      // uno debe partir del estado más reciente, no de uno anterior a la espera.
      final ticket = await _repository.getRequest(requestId);
      emit(state.copyWith(status: LoadStatus.success, ticket: ticket, clearFailure: true));
    } catch (error) {
      emit(state.copyWith(status: LoadStatus.failure, failure: toFailure(error), clearTicket: true));
    } finally {
      event.done?.complete();
    }
  }

  Future<void> _onWorkflow(RequestWorkflowRequested event, Emitter<RequestDetailState> emit) async {
    try {
      // Se espera antes de leer `state`: el ticket puede haber llegado mientras tanto y no hay que pisarlo.
      final workflow = await _repository.workflow();
      emit(state.copyWith(workflow: workflow));
    } catch (_) {
      // Sin el flujo no se ofrecen acciones; el detalle sigue siendo de lectura.
    }
  }

  /// Cambia el estado y recarga el ticket. Termina siempre con un aviso (bien o con el motivo del
  /// fallo): sube [RequestDetailState.changeSerial] para que la pantalla lo muestre una vez.
  Future<void> _onStatusChange(RequestStatusChangeRequested event, Emitter<RequestDetailState> emit) async {
    if (state.changing) return;
    emit(state.copyWith(changing: true, clearChange: true));
    try {
      await _repository.transitionStatus(requestId, event.target, notes: event.notes, resolutionSummary: event.resolutionSummary);
      // El cambio ya está hecho: si recargar falla, se avisa igual de que salió bien.
      TicketDetail? ticket;
      try {
        ticket = await _repository.getRequest(requestId);
      } catch (_) {}
      emit(state.copyWith(changing: false, ticket: ticket, changeSerial: state.changeSerial + 1, changedTo: event.target));
    } catch (error) {
      emit(state.copyWith(changing: false, changeSerial: state.changeSerial + 1, changeFailure: toFailure(error)));
    }
  }

  Future<void> _onAttachments(RequestAttachmentsRequested event, Emitter<RequestDetailState> emit) async {
    emit(state.copyWith(attachmentsStatus: LoadStatus.loading));
    try {
      final attachments = await _repository.listAttachments(requestId);
      emit(state.copyWith(attachmentsStatus: LoadStatus.success, attachments: attachments));
    } catch (_) {
      emit(state.copyWith(attachmentsStatus: LoadStatus.failure));
    }
  }
}
