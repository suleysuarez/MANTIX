part of 'equipment_export_bloc.dart';

sealed class EquipmentExportEvent {
  const EquipmentExportEvent();
}

/// Exporta el inventario en [format], con el filtro de estado y de categoría vigentes (el de
/// texto no existe en el servidor).
class EquipmentExportRequested extends EquipmentExportEvent {
  const EquipmentExportRequested(this.format, {this.statuses, this.typeId});

  final ExportFormat format;
  final String? statuses;
  final int? typeId;
}
