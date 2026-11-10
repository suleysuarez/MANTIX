part of 'equipment_detail_bloc.dart';

sealed class EquipmentDetailEvent {
  const EquipmentDetailEvent();
}

/// Carga el historial de tickets y los adjuntos del equipo (o los reintenta).
class EquipmentDetailStarted extends EquipmentDetailEvent {
  const EquipmentDetailStarted();
}
