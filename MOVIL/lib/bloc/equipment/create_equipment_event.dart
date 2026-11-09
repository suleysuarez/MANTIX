part of 'create_equipment_bloc.dart';

sealed class CreateEquipmentEvent {
  const CreateEquipmentEvent();
}

/// Carga (o reintenta) las categorías del desplegable.
class CreateEquipmentStarted extends CreateEquipmentEvent {
  const CreateEquipmentStarted();
}

class CreateEquipmentSubmitted extends CreateEquipmentEvent {
  const CreateEquipmentSubmitted(this.equipment);

  final NewEquipment equipment;
}
