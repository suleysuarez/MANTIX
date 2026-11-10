import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/equipment/equipment_models.dart';
import '../../repositories/equipment/equipment_repository.dart';

/// Código del 409 cuando ya existe una categoría con ese nombre (sin distinguir mayúsculas).
const equipmentTypeNameTaken = 'equipment_type_name_taken';

sealed class CreateEquipmentTypeEvent {
  const CreateEquipmentTypeEvent();
}

/// Crea una categoría con [name] (ya recortado y con los espacios colapsados).
class EquipmentTypeSubmitted extends CreateEquipmentTypeEvent {
  const EquipmentTypeSubmitted(this.name);

  final String name;
}

enum CreateTypeStatus { idle, submitting, success, conflict, failure }

class CreateEquipmentTypeState extends Equatable {
  const CreateEquipmentTypeState({this.status = CreateTypeStatus.idle, this.name = '', this.created, this.failure});

  final CreateTypeStatus status;

  /// Nombre que se intentó crear (para ofrecer la categoría que ya existe con ese nombre).
  final String name;
  final EquipmentType? created;
  final Failure? failure;

  @override
  List<Object?> get props => [status, name, created, failure];
}

/// Alta de una categoría desde el selector del formulario de equipo. Un 409
/// `equipment_type_name_taken` no es un fallo: es el caso «ya existe» y la pantalla ofrece usar
/// la que existe.
class CreateEquipmentTypeBloc extends Bloc<CreateEquipmentTypeEvent, CreateEquipmentTypeState> {
  CreateEquipmentTypeBloc({required this._repository}) : super(const CreateEquipmentTypeState()) {
    on<EquipmentTypeSubmitted>(_onSubmitted);
  }

  final EquipmentRepository _repository;

  Future<void> _onSubmitted(EquipmentTypeSubmitted event, Emitter<CreateEquipmentTypeState> emit) async {
    if (state.status == CreateTypeStatus.submitting) return;
    emit(CreateEquipmentTypeState(status: CreateTypeStatus.submitting, name: event.name));
    try {
      final created = await _repository.createType(event.name);
      emit(CreateEquipmentTypeState(status: CreateTypeStatus.success, name: event.name, created: created));
    } catch (error) {
      final failure = toFailure(error);
      emit(CreateEquipmentTypeState(
        status: failure is ConflictFailure && failure.code == equipmentTypeNameTaken ? CreateTypeStatus.conflict : CreateTypeStatus.failure,
        name: event.name,
        failure: failure,
      ));
    }
  }
}
