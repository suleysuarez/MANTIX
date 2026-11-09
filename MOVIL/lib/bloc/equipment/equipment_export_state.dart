part of 'equipment_export_bloc.dart';

enum ExportStatus { idle, working, shared, empty, failure }

class EquipmentExportState extends Equatable {
  const EquipmentExportState({this.status = ExportStatus.idle, this.progress, this.message});

  final ExportStatus status;

  /// Avance de la descarga, de 0 a 1 (`null` si el servidor no dice el tamaño).
  final double? progress;

  /// Mensaje en español para `empty` y `failure`.
  final String? message;

  @override
  List<Object?> get props => [status, progress, message];
}
