part of 'create_equipment_bloc.dart';

sealed class CreateEquipmentEvent {
  const CreateEquipmentEvent();
}

class CreateEquipmentSubmitted extends CreateEquipmentEvent {
  const CreateEquipmentSubmitted(this.equipment);

  final NewEquipment equipment;
}
