part of 'request_board_bloc.dart';

enum ColumnPhase { loading, ready, failure }

/// Una columna del tablero: un estado de la cola con sus tarjetas por páginas.
class BoardColumn extends Equatable {
  const BoardColumn({required this.status, this.items = const [], this.total = 0, this.nextPage, this.phase = ColumnPhase.loading, this.loadingMore = false, this.failure});

  final String status;
  final List<TicketListItem> items;

  /// Total del servidor (`X-Total-Count`); puede ser mayor que las tarjetas cargadas.
  final int total;

  /// Siguiente página por pedir, o `null` si ya están todas.
  final int? nextPage;
  final ColumnPhase phase;
  final bool loadingMore;
  final Failure? failure;

  bool get hasMore => nextPage != null;

  /// Cuántas faltan por cargar.
  int get remaining => (total - items.length).clamp(0, total);

  BoardColumn copyWith({List<TicketListItem>? items, int? total, int? nextPage, bool clearNextPage = false, ColumnPhase? phase, bool? loadingMore, Failure? failure, bool clearFailure = false}) => BoardColumn(
        status: status,
        items: items ?? this.items,
        total: total ?? this.total,
        nextPage: clearNextPage ? null : (nextPage ?? this.nextPage),
        phase: phase ?? this.phase,
        loadingMore: loadingMore ?? this.loadingMore,
        failure: clearFailure ? null : (failure ?? this.failure),
      );

  @override
  List<Object?> get props => [status, items, total, nextPage, phase, loadingMore, failure];
}

enum WorkflowPhase { loading, ready, failure }

class RequestBoardState extends Equatable {
  const RequestBoardState({this.workflowPhase = WorkflowPhase.loading, this.workflow = const QueueWorkflow(), this.columns = const [], this.filters = const QueueFilters(), this.failure});

  final WorkflowPhase workflowPhase;
  final QueueWorkflow workflow;
  final List<BoardColumn> columns;
  final QueueFilters filters;

  /// Error al cargar el flujo (sin él no hay columnas).
  final Failure? failure;

  BoardColumn? column(String status) => columns.where((c) => c.status == status).firstOrNull;

  /// El tablero está al día: todas las columnas cargaron y ninguna tiene tarjetas.
  bool get isEmpty => workflowPhase == WorkflowPhase.ready && columns.isNotEmpty && columns.every((c) => c.phase == ColumnPhase.ready && c.items.isEmpty);

  RequestBoardState copyWith({WorkflowPhase? workflowPhase, QueueWorkflow? workflow, List<BoardColumn>? columns, QueueFilters? filters, Failure? failure, bool clearFailure = false}) => RequestBoardState(
        workflowPhase: workflowPhase ?? this.workflowPhase,
        workflow: workflow ?? this.workflow,
        columns: columns ?? this.columns,
        filters: filters ?? this.filters,
        failure: clearFailure ? null : (failure ?? this.failure),
      );

  @override
  List<Object?> get props => [workflowPhase, workflow, columns, filters, failure];
}
