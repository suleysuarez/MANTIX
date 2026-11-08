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
