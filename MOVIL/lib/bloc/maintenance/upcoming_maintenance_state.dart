part of 'upcoming_maintenance_bloc.dart';

enum UpcomingStatus { loading, ready, failure }

/// Rango de «Servicios entre». [all] deja lo cargado (vencidos y programados); los otros miran solo
/// desde hoy: el mismo día, los próximos 7 días o los próximos 30.
enum UpcomingRange { all, today, week, month }

class UpcomingMaintenanceState extends Equatable {
  const UpcomingMaintenanceState({this.status = UpcomingStatus.loading, this.items = const [], this.failure, this.range = UpcomingRange.all, this.today});

  final UpcomingStatus status;

  /// Los vencidos primero y luego los programados, del más próximo al más lejano. Siguen visibles
  /// mientras se recarga o si la recarga falla.
  final List<CalendarEvent> items;
  final Failure? failure;
  final UpcomingRange range;

  /// El día con el que se calculó [items]; los rangos se miden desde él.
  final DateTime? today;

  /// Lo que se ve con el [range] elegido.
  List<CalendarEvent> get visibleItems {
    final from = today;
    if (range == UpcomingRange.all || from == null) return items;
    final days = switch (range) { UpcomingRange.today => 1, UpcomingRange.week => 8, _ => 31 };
    final to = addDays(from, days);
    return [for (final event in items) if (!event.at.isBefore(from) && event.at.isBefore(to)) event];
  }

  bool get initialLoading => status == UpcomingStatus.loading && items.isEmpty;

  /// Se muestra el error con reintento solo si no hay nada que enseñar.
  bool get unavailable => status == UpcomingStatus.failure && items.isEmpty;

  UpcomingMaintenanceState copyWith({UpcomingStatus? status, List<CalendarEvent>? items, Failure? failure, bool clearFailure = false, UpcomingRange? range, DateTime? today}) => UpcomingMaintenanceState(
        status: status ?? this.status,
        items: items ?? this.items,
        failure: clearFailure ? null : (failure ?? this.failure),
        range: range ?? this.range,
        today: today ?? this.today,
      );

  @override
  List<Object?> get props => [status, items, failure, range, today];
}
