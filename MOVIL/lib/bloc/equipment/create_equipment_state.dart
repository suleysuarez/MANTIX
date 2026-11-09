part of 'create_equipment_bloc.dart';

enum TypesStatus { loading, success, failure }

enum CreateEquipmentStatus { initial, submitting, success, failure }

class CreateEquipmentState extends Equatable {
  const CreateEquipmentState({
    this.typesStatus = TypesStatus.loading,
    this.types = const [],
    this.typesFailure,
    this.status = CreateEquipmentStatus.initial,
    this.created,
    this.failure,
  });

  final TypesStatus typesStatus;
  final List<EquipmentType> types;
  final Failure? typesFailure;

  final CreateEquipmentStatus status;

  /// Equipo registrado (solo en `success`).
  final Equipment? created;

  /// Motivo del fallo (solo en `failure`); un [ValidationFailure] trae los errores por campo.
  final Failure? failure;

  CreateEquipmentState copyWith({
    TypesStatus? typesStatus,
    List<EquipmentType>? types,
    Failure? typesFailure,
    CreateEquipmentStatus? status,
    Equipment? created,
    Failure? failure,
    bool clearFailure = false,
  }) =>
      CreateEquipmentState(
        typesStatus: typesStatus ?? this.typesStatus,
        types: types ?? this.types,
        typesFailure: typesStatus == TypesStatus.success ? null : (typesFailure ?? this.typesFailure),
        status: status ?? this.status,
        created: created ?? this.created,
        failure: clearFailure ? null : (failure ?? this.failure),
      );

  @override
  List<Object?> get props => [typesStatus, types, typesFailure, status, created, failure];
}
