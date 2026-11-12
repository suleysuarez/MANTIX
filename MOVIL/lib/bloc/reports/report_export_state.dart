part of 'report_export_bloc.dart';

/// [shared] el archivo se generó y se abrió la hoja de compartir; [empty] el servidor no devolvió
/// datos; [failure] algo falló (el motivo está en `message`).
enum ExportStatus { idle, working, shared, empty, failure }

class ReportExportState extends Equatable {
  const ReportExportState({this.status = ExportStatus.idle, this.progress, this.message, this.fileName, this.format});

  final ExportStatus status;

  /// De 0 a 1 mientras se descarga; `null` si aún no se sabe.
  final double? progress;
  final String? message;

  /// El archivo compartido, cuando [status] es [ExportStatus.shared].
  final String? fileName;
  final ReportFormat? format;

  bool get working => status == ExportStatus.working;

  @override
  List<Object?> get props => [status, progress, message, fileName, format];
}
