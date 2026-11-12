part of 'report_history_bloc.dart';

enum HistoryStatus { loading, success, failure }

class ReportHistoryState extends Equatable {
  const ReportHistoryState({this.status = HistoryStatus.loading, this.items = const [], this.info, this.page = 1, this.loadingPage = false, this.failure});

  final HistoryStatus status;

  /// Las exportaciones de la página actual.
  final List<ReportRun> items;

  /// Paginación de la última respuesta; `null` si el servidor no la envió (una sola página).
  final PageInfo? info;

  /// Página pedida (base 1).
  final int page;

  /// Se está pidiendo otra página mientras se siguen mostrando los datos anteriores.
  final bool loadingPage;

  /// El motivo del último fallo; con datos a la vista, la recarga que falló no los quita.
  final Failure? failure;

  int get total => info?.total ?? items.length;
  int get totalPages => info?.totalPages ?? 1;

  ReportHistoryState copyWith({int? page, bool? loadingPage, Failure? failure}) => ReportHistoryState(status: status, items: items, info: info, page: page ?? this.page, loadingPage: loadingPage ?? this.loadingPage, failure: failure ?? this.failure);

  @override
  List<Object?> get props => [status, items, info, page, loadingPage, failure];
}
