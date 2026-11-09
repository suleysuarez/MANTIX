import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/equipment/equipment_models.dart';
import '../../repositories/equipment/equipment_repository.dart';

part 'create_equipment_event.dart';
part 'create_equipment_state.dart';

/// Alta de un equipo: registra el equipo y, si el formulario trae ubicación o responsable,
/// los asigna con sus propios endpoints. La validación de campos vive en el formulario; aquí solo
/// se envía, se evita el doble envío y se informa del resultado.
///
/// Si el equipo se registra pero una asignación falla, el alta cuenta como hecha (el equipo ya
/// existe) y el motivo llega en [CreateEquipmentState.warnings], sin deshacer nada.
class CreateEquipmentBloc extends Bloc<CreateEquipmentEvent, CreateEquipmentState> {
  CreateEquipmentBloc({required this._repository}) : super(const CreateEquipmentState()) {
    on<CreateEquipmentSubmitted>(_onSubmitted);
  }

  final EquipmentRepository _repository;

  Future<void> _onSubmitted(CreateEquipmentSubmitted event, Emitter<CreateEquipmentState> emit) async {
    if (state.status == CreateEquipmentStatus.submitting) return;
    emit(const CreateEquipmentState(status: CreateEquipmentStatus.submitting));
    final form = event.equipment;
    final Equipment created;
    try {
      created = await _repository.create(form);
    } catch (error) {
      emit(CreateEquipmentState(status: CreateEquipmentStatus.failure, failure: toFailure(error)));
      return;
    }
    final warnings = <String>[];
    Future<void> assign(String what, Future<void> Function() call) async {
      try {
        await call();
      } catch (error) {
        warnings.add('No se pudo asignar $what: ${toFailure(error).message}');
      }
    }

    final locationId = form.locationId;
    final custodianId = form.custodianId;
    if (locationId != null) await assign('la ubicación', () => _repository.assignLocation(created.id, locationId));
    if (custodianId != null) await assign('el responsable', () => _repository.assignCustody(created.id, custodianId));
    emit(CreateEquipmentState(status: CreateEquipmentStatus.success, created: created, warnings: warnings));
  }
}
