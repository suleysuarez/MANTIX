part of 'upcoming_maintenance_bloc.dart';

sealed class UpcomingMaintenanceEvent {
  const UpcomingMaintenanceEvent();
}

/// Carga o recarga los próximos mantenimientos.
class UpcomingRequested extends UpcomingMaintenanceEvent {
  const UpcomingRequested({this.done});

  /// Se completa al terminar (tirar para refrescar espera a esto).
  final Completer<void>? done;
}
