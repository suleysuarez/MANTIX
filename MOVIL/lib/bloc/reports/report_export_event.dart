part of 'report_export_bloc.dart';

sealed class ReportExportEvent {
  const ReportExportEvent();
}

/// Exportar [definition] en [format] con estos filtros. Solo viaja lo que el reporte admite.
class ReportExportRequested extends ReportExportEvent {
  const ReportExportRequested({required this.definition, required this.format, required this.values});

  final ReportDefinition definition;
  final ReportFormat format;
  final ReportFilterValues values;
}

/// Cierra el aviso de «archivo generado» o de error y vuelve al estado inicial (no hace nada si
/// hay una exportación en curso).
class ReportExportDismissed extends ReportExportEvent {
  const ReportExportDismissed();
}
