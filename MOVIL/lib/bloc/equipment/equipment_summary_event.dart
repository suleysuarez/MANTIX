part of 'equipment_summary_bloc.dart';

sealed class EquipmentSummaryEvent {
  const EquipmentSummaryEvent();
}

/// Primera carga (o reintento tras un error).
class EquipmentSummaryStarted extends EquipmentSummaryEvent {
  const EquipmentSummaryStarted();
}

/// Vuelve a pedir los contadores; con datos ya cargados se siguen mostrando.
class EquipmentSummaryRefreshed extends EquipmentSummaryEvent {
  const EquipmentSummaryRefreshed({this.done});

  /// Se completa al terminar; el «tirar para refrescar» espera a que acabe.
  final Completer<void>? done;
}
