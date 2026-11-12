part of 'upcoming_maintenance_bloc.dart';

sealed class UpcomingMaintenanceEvent {
  const UpcomingMaintenanceEvent();
}

/// Cambia el rango de «Servicios entre» (todo, hoy, próximos 7 o 30 días). No pide nada al
/// servidor: filtra lo que ya cargó.
class UpcomingRangeChanged extends UpcomingMaintenanceEvent {
  const UpcomingRangeChanged(this.range);

  final UpcomingRange range;
}

/// Carga o recarga los próximos mantenimientos.
class UpcomingRequested extends UpcomingMaintenanceEvent {
  const UpcomingRequested({this.done});

  /// Se completa al terminar (tirar para refrescar espera a esto).
  final Completer<void>? done;
}
