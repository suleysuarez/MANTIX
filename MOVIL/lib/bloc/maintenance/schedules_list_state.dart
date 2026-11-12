part of 'schedules_list_bloc.dart';

enum SchedulesStatus { loading, success, failure }

class SchedulesListState extends Equatable {
  const SchedulesListState({this.status = SchedulesStatus.loading, this.items = const [], this.info, this.page = 1, this.loadingPage = false, this.failure});

  final SchedulesStatus status;

  /// Planes de la página actual.
  final List<MaintenanceSchedule> items;

  /// Paginación de la última respuesta; `null` si el servidor no la envió (una sola página).
  final PageInfo? info;

  /// Página pedida (base 1).
  final int page;

  /// Se está pidiendo otra página mientras se siguen mostrando los datos anteriores.
  final bool loadingPage;
  final Failure? failure;

  int get total => info?.total ?? items.length;
  int get totalPages => info?.totalPages ?? 1;

  SchedulesListState copyWith({int? page, bool? loadingPage}) => SchedulesListState(status: status, items: items, info: info, page: page ?? this.page, loadingPage: loadingPage ?? this.loadingPage, failure: failure);

  @override
  List<Object?> get props => [status, items, info, page, loadingPage, failure];
}
