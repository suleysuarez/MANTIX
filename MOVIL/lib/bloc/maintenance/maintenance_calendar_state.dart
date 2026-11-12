part of 'maintenance_calendar_bloc.dart';

enum CalendarStatus { loading, ready, failure }

class MaintenanceCalendarState extends Equatable {
  const MaintenanceCalendarState({required this.anchor, this.status = CalendarStatus.loading, this.events = const [], this.truncated = false, this.selectedKey, this.failure});

  /// Primer día del mes que se ve.
  final DateTime anchor;
  final CalendarStatus status;

  /// Los servicios de la cuadrícula del mes (incluye algunos días de los meses vecinos).
  final List<CalendarEvent> events;

  /// El servidor llegó a su tope: puede haber más servicios de los que se ven.
  final bool truncated;

  /// Día elegido (`YYYY-MM-DD`), o `null`.
  final String? selectedKey;
  final Failure? failure;

  bool get loading => status == CalendarStatus.loading;

  /// Los servicios de cada día de la cuadrícula.
  Map<String, List<CalendarEvent>> get byDay => groupByDay(events);

  /// Los servicios del día elegido, por hora.
  List<CalendarEvent> get selectedEvents => [...?byDay[selectedKey]]..sort((a, b) => a.at.compareTo(b.at));

  MaintenanceCalendarState copyWith({DateTime? anchor, CalendarStatus? status, List<CalendarEvent>? events, bool? truncated, String? selectedKey, bool clearSelected = false, Failure? failure, bool clearFailure = false}) => MaintenanceCalendarState(
        anchor: anchor ?? this.anchor,
        status: status ?? this.status,
        events: events ?? this.events,
        truncated: truncated ?? this.truncated,
        selectedKey: clearSelected ? null : (selectedKey ?? this.selectedKey),
        failure: clearFailure ? null : (failure ?? this.failure),
      );

  @override
  List<Object?> get props => [anchor, status, events, truncated, selectedKey, failure];
}
