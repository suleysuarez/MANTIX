import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/equipment/equipment_models.dart';
import '../../repositories/equipment/equipment_repository.dart';

part 'create_equipment_event.dart';
part 'create_equipment_state.dart';

/// Formulario «Nuevo equipo»: carga las categorías y envía el alta. La validación de campos vive
/// en el formulario; aquí solo se envía, se evita el doble envío y se informa del resultado.
class CreateEquipmentBloc extends Bloc<CreateEquipmentEvent, CreateEquipmentState> {
  CreateEquipmentBloc({required this._repository}) : super(const CreateEquipmentState()) {
    on<CreateEquipmentStarted>(_onStarted);
    on<CreateEquipmentSubmitted>(_onSubmitted);
  }

  final EquipmentRepository _repository;

  Future<void> _onStarted(CreateEquipmentStarted event, Emitter<CreateEquipmentState> emit) async {
    emit(state.copyWith(typesStatus: TypesStatus.loading));
    try {
      emit(state.copyWith(typesStatus: TypesStatus.success, types: await _repository.types()));
    } catch (error) {
      emit(state.copyWith(typesStatus: TypesStatus.failure, typesFailure: toFailure(error)));
    }
  }

  Future<void> _onSubmitted(CreateEquipmentSubmitted event, Emitter<CreateEquipmentState> emit) async {
    if (state.status == CreateEquipmentStatus.submitting) return;
    emit(state.copyWith(status: CreateEquipmentStatus.submitting, clearFailure: true));
    try {
      final created = await _repository.create(event.equipment);
      emit(state.copyWith(status: CreateEquipmentStatus.success, created: created));
    } catch (error) {
      emit(state.copyWith(status: CreateEquipmentStatus.failure, failure: toFailure(error)));
    }
  }
}
