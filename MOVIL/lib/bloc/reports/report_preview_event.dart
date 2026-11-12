part of 'report_preview_bloc.dart';

sealed class ReportPreviewEvent {
  const ReportPreviewEvent();
}

/// Pide la vista previa con estos filtros (al abrir, al aplicar filtros, al cambiar el comparativo
/// o al reintentar).
class ReportPreviewRequested extends ReportPreviewEvent {
  const ReportPreviewRequested(this.values);

  final ReportFilterValues values;
}
