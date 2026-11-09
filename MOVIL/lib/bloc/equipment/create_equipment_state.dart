part of 'create_equipment_bloc.dart';

enum CreateEquipmentStatus { initial, submitting, success, failure }

class CreateEquipmentState extends Equatable {
  const CreateEquipmentState({this.status = CreateEquipmentStatus.initial, this.created, this.warnings = const [], this.failure});

  final CreateEquipmentStatus status;

  /// Equipo registrado (solo en `success`).
  final Equipment? created;

  /// Asignaciones (ubicación, responsable) que no se pudieron hacer tras registrar el equipo.
  final List<String> warnings;

  /// Motivo del fallo (solo en `failure`); un [ValidationFailure] trae los errores por campo.
  final Failure? failure;

  @override
  List<Object?> get props => [status, created, warnings, failure];
}
