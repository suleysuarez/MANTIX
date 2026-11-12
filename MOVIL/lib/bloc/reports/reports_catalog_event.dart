part of 'reports_catalog_bloc.dart';

sealed class ReportsCatalogEvent {
  const ReportsCatalogEvent();
}

/// Carga o recarga el catálogo (al abrir, al tirar para refrescar o al reintentar).
class ReportsCatalogRequested extends ReportsCatalogEvent {
  const ReportsCatalogRequested({this.done});

  /// Se completa cuando termina la carga (tirar para refrescar espera a esto).
  final Completer<void>? done;
}

/// Elige un reporte de la galería por su clave (`tickets`, `maintenance_plans`…).
class ReportSelected extends ReportsCatalogEvent {
  const ReportSelected(this.key);

  final String key;
}
