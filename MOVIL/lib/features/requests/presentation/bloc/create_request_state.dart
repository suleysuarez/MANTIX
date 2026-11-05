part of 'create_request_bloc.dart';

enum CreateStatus { initial, submitting, success, failure }

class CreateRequestState extends Equatable {
  const CreateRequestState({this.status = CreateStatus.initial, this.createdId, this.failure});

  final CreateStatus status;

  /// Id del ticket creado (solo en `success`).
  final int? createdId;

  /// Motivo del fallo (solo en `failure`); un [ValidationFailure] trae los errores por campo.
  final Failure? failure;

  @override
  List<Object?> get props => [status, createdId, failure];
}
