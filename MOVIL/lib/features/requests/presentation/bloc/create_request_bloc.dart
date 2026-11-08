import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../models/requests/request_models.dart';
import '../../../../repositories/requests/requests_repository.dart';

part 'create_request_event.dart';
part 'create_request_state.dart';

/// Envío del formulario de nueva solicitud. La validación de campos vive en el
/// formulario; aquí solo se envía, se evita el doble envío y se informa del resultado.
class CreateRequestBloc extends Bloc<CreateRequestEvent, CreateRequestState> {
  CreateRequestBloc({required this._repository}) : super(const CreateRequestState()) {
    on<CreateRequestSubmitted>(_onSubmitted);
  }

  final RequestsRepository _repository;

  Future<void> _onSubmitted(CreateRequestSubmitted event, Emitter<CreateRequestState> emit) async {
    if (state.status == CreateStatus.submitting) return;
    emit(const CreateRequestState(status: CreateStatus.submitting));
    try {
      final created = await _repository.create(event.request);
      emit(CreateRequestState(status: CreateStatus.success, createdId: created.id));
    } catch (error) {
      emit(CreateRequestState(status: CreateStatus.failure, failure: toFailure(error)));
    }
  }
}
