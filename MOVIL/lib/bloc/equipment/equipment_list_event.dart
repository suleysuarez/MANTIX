part of 'equipment_list_bloc.dart';

sealed class EquipmentListEvent {
  const EquipmentListEvent();
}

/// Primera carga (página 1).
class EquipmentListStarted extends EquipmentListEvent {
  const EquipmentListStarted();
}

/// Cambia de página (base 1).
class EquipmentPageSelected extends EquipmentListEvent {
  const EquipmentPageSelected(this.page);

  final int page;
}

/// Vuelve a pedir la página actual; con datos cargados se siguen mostrando.
class EquipmentListRefreshed extends EquipmentListEvent {
  const EquipmentListRefreshed({this.done});

  /// Se completa al terminar; el «tirar para refrescar» espera a que acabe.
  final Completer<void>? done;
}
