part of 'maintenance_calendar_bloc.dart';

sealed class MaintenanceCalendarEvent {
  const MaintenanceCalendarEvent();
}

/// Carga o recarga el mes visible (al abrir, al tirar para refrescar, al reintentar o tras un cambio).
class CalendarRequested extends MaintenanceCalendarEvent {
  const CalendarRequested({this.done});

  /// Se completa cuando termina la carga (tirar para refrescar espera a esto).
  final Completer<void>? done;
}

/// Pasa al mes anterior (−1) o al siguiente (1).
class CalendarMonthShifted extends MaintenanceCalendarEvent {
  const CalendarMonthShifted(this.direction);

  final int direction;
}

/// Vuelve al mes de hoy y elige el día de hoy.
class CalendarTodayRequested extends MaintenanceCalendarEvent {
  const CalendarTodayRequested();
}

/// Elige un día (`YYYY-MM-DD`); tocar el que ya está elegido lo quita, y `null` quita la elección.
class CalendarDaySelected extends MaintenanceCalendarEvent {
  const CalendarDaySelected(this.key);

  final String? key;
}
