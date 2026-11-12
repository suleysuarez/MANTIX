part of 'upcoming_maintenance_bloc.dart';

enum UpcomingStatus { loading, ready, failure }

class UpcomingMaintenanceState extends Equatable {
  const UpcomingMaintenanceState({this.status = UpcomingStatus.loading, this.items = const [], this.failure});

  final UpcomingStatus status;

  /// Los vencidos primero y luego los programados, del más próximo al más lejano. Siguen visibles
  /// mientras se recarga o si la recarga falla.
  final List<CalendarEvent> items;
  final Failure? failure;

  bool get initialLoading => status == UpcomingStatus.loading && items.isEmpty;

  /// Se muestra el error con reintento solo si no hay nada que enseñar.
  bool get unavailable => status == UpcomingStatus.failure && items.isEmpty;

  UpcomingMaintenanceState copyWith({UpcomingStatus? status, List<CalendarEvent>? items, Failure? failure, bool clearFailure = false}) => UpcomingMaintenanceState(
        status: status ?? this.status,
        items: items ?? this.items,
        failure: clearFailure ? null : (failure ?? this.failure),
      );

  @override
  List<Object?> get props => [status, items, failure];
}
