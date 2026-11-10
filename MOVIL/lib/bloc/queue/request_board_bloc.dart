import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/queue/queue_filters.dart';
import '../../models/queue/queue_workflow.dart';
import '../../models/page_info.dart';
import '../../models/requests/request_models.dart';
import '../../repositories/requests/requests_repository.dart';

part 'request_board_event.dart';
part 'request_board_state.dart';

/// Tablero de la bandeja de triaje: una columna por cada estado `in_queue` del flujo del
/// servidor, cada una con su propia página, su carga y su error. Nunca se pide el catálogo
/// completo: 10 tarjetas por columna y «Ver más».
class RequestBoardBloc extends Bloc<RequestBoardEvent, RequestBoardState> {
  RequestBoardBloc({required this._repository, this.searchDebounce = const Duration(milliseconds: 300)}) : super(const RequestBoardState()) {
    on<RequestBoardStarted>(_onStarted);
    on<RequestBoardRefreshed>(_onRefreshed);
    on<RequestBoardFiltersChanged>(_onFiltersChanged);
    on<RequestBoardSearchChanged>(_onSearchChanged);
    on<RequestBoardMoreRequested>(_onMore);
    on<RequestBoardColumnRetried>(_onRetry);
    on<RequestBoardMovedOptimistically>(_onMoved);
    on<RequestBoardMoveReverted>(_onReverted);
  }

  /// Tarjetas que se piden por columna y por vez.
  static const columnPageSize = 10;

  final RequestsRepository _repository;
  final Duration searchDebounce;

  /// Se suma con cada recarga completa: una respuesta de una recarga anterior se descarta.
  int _generation = 0;
  int _searches = 0;

  /// Dónde estaba cada tarjeta movida y todavía sin confirmar, para devolverla si falla.
  final Map<int, ({TicketListItem ticket, int index})> _origins = {};

  Future<void> _onStarted(RequestBoardStarted event, Emitter<RequestBoardState> emit) async {
    emit(state.copyWith(workflowPhase: WorkflowPhase.loading, clearFailure: true));
    try {
      final workflow = QueueWorkflow(await _repository.workflow());
      emit(state.copyWith(
        workflowPhase: WorkflowPhase.ready,
        workflow: workflow,
        columns: [for (final status in workflow.columns) BoardColumn(status: status.status)],
      ));
      await _loadAll(emit, silent: false);
    } catch (error) {
      emit(state.copyWith(workflowPhase: WorkflowPhase.failure, failure: toFailure(error)));
    }
  }

  Future<void> _onRefreshed(RequestBoardRefreshed event, Emitter<RequestBoardState> emit) async {
    try {
      if (state.workflowPhase != WorkflowPhase.ready) {
        await _onStarted(const RequestBoardStarted(), emit);
        return;
      }
      await _loadAll(emit, silent: true);
    } finally {
      event.done?.complete();
    }
  }

  Future<void> _onFiltersChanged(RequestBoardFiltersChanged event, Emitter<RequestBoardState> emit) async {
    if (event.filters == state.filters) return;
    await _loadAll(emit, silent: false, filters: event.filters);
  }

  Future<void> _onSearchChanged(RequestBoardSearchChanged event, Emitter<RequestBoardState> emit) async {
    final turn = ++_searches;
    final term = event.term.trim();
    if (term == state.filters.search.trim()) return;
    await Future<void>.delayed(searchDebounce);
    if (turn != _searches || emit.isDone) return;
    await _loadAll(emit, silent: false, filters: state.filters.copyWith(search: term));
  }

  Future<void> _onMore(RequestBoardMoreRequested event, Emitter<RequestBoardState> emit) async {
    final column = state.column(event.status);
    final page = column?.nextPage;
    if (column == null || page == null || column.loadingMore || column.phase != ColumnPhase.ready) return;
    final generation = _generation;
    _replace(emit, column.copyWith(loadingMore: true, clearFailure: true));
    try {
      final result = await _fetch(event.status, page);
      if (generation != _generation) return;
      final current = state.column(event.status)!;
      final known = {for (final item in current.items) item.id};
      _replace(emit, current.copyWith(
        items: [...current.items, for (final item in result.items) if (!known.contains(item.id)) item],
        total: result.info?.total ?? current.total,
        nextPage: result.info?.nextPage,
        clearNextPage: result.info?.nextPage == null,
        loadingMore: false,
      ));
    } catch (error) {
      if (generation != _generation) return;
      // El error de «Ver más» no tira las tarjetas ya cargadas: queda el botón para reintentar.
      _replace(emit, state.column(event.status)!.copyWith(loadingMore: false, failure: toFailure(error)));
    }
  }

  Future<void> _onRetry(RequestBoardColumnRetried event, Emitter<RequestBoardState> emit) async {
    final column = state.column(event.status);
    if (column == null) return;
    final generation = _generation;
    _replace(emit, column.copyWith(phase: ColumnPhase.loading, clearFailure: true));
    await _loadColumn(event.status, generation, emit, silent: false);
  }

  void _onMoved(RequestBoardMovedOptimistically event, Emitter<RequestBoardState> emit) {
    final ticket = event.ticket;
    final source = state.column(ticket.status);
    final index = source?.items.indexWhere((item) => item.id == ticket.id) ?? -1;
    if (source == null || index < 0) return;
    _origins[ticket.id] = (ticket: ticket, index: index);
    final moved = ticket.withStatus(event.target);
    final columns = [
      for (final column in state.columns)
        if (column.status == ticket.status)
          column.copyWith(items: [...column.items]..removeAt(index), total: _atLeastZero(column.total - 1))
        else if (column.status == event.target)
          column.copyWith(items: [moved, ...column.items], total: column.total + 1)
        else
          column,
    ];
    emit(state.copyWith(columns: columns));
  }

  void _onReverted(RequestBoardMoveReverted event, Emitter<RequestBoardState> emit) {
    final origin = _origins.remove(event.ticketId);
    if (origin == null) return;
    // Si el destino no es una columna (rechazar), la tarjeta ya no está en el tablero: se
    // devuelve la que había antes de moverla.
    final columns = [
      for (final column in state.columns)
        if (column.status == origin.ticket.status)
          _withTicketAt(column, origin.ticket, origin.index, event.ticketId)
        else if (column.items.any((item) => item.id == event.ticketId))
          column.copyWith(items: [for (final item in column.items) if (item.id != event.ticketId) item], total: _atLeastZero(column.total - 1))
        else
          column,
    ];
    emit(state.copyWith(columns: columns));
  }

  /// [column] con [ticket] en [index] (o al final si ya no cabe) y sin otra copia de [id].
  BoardColumn _withTicketAt(BoardColumn column, TicketListItem ticket, int index, int id) {
    final items = [for (final item in column.items) if (item.id != id) item];
    items.insert(index.clamp(0, items.length), ticket);
    return column.copyWith(items: items, total: column.total + 1);
  }

  int _atLeastZero(int value) => value < 0 ? 0 : value;

  void _replace(Emitter<RequestBoardState> emit, BoardColumn column) {
    if (emit.isDone) return;
    emit(state.copyWith(columns: [for (final c in state.columns) c.status == column.status ? column : c]));
  }

  Future<PagedResult<TicketListItem>> _fetch(String status, int page) {
    final filters = state.filters;
    return _repository.listRequests(
      page: page,
      size: columnPageSize,
      status: status,
      search: filters.search,
      dateFrom: filters.dateFrom,
      dateTo: filters.dateTo,
      priorities: filters.priorities,
      categories: filters.categories,
      technicianIds: filters.technicianIds,
    );
  }

  /// Pide la primera página de todas las columnas a la vez; cada una carga y falla por separado.
  Future<void> _loadAll(Emitter<RequestBoardState> emit, {required bool silent, QueueFilters? filters}) async {
    final generation = ++_generation;
    _origins.clear();
    // Los filtros nuevos y las columnas vacías van en un solo cambio: no hay un cuadro intermedio
    // con filtros nuevos y tarjetas viejas.
    if (!silent || filters != null) {
      emit(state.copyWith(filters: filters, columns: [for (final column in state.columns) BoardColumn(status: column.status)]));
    }
    await Future.wait([for (final column in state.columns) _loadColumn(column.status, generation, emit, silent: silent)]);
  }

  Future<void> _loadColumn(String status, int generation, Emitter<RequestBoardState> emit, {required bool silent}) async {
    try {
      final result = await _fetch(status, 1);
      if (generation != _generation || emit.isDone) return;
      _replace(emit, BoardColumn(
        status: status,
        items: result.items,
        total: result.info?.total ?? result.items.length,
        nextPage: result.info?.nextPage,
        phase: ColumnPhase.ready,
      ));
    } catch (error) {
      if (generation != _generation || emit.isDone) return;
      final column = state.column(status)!;
      // Una recarga silenciosa que falla deja las tarjetas que ya había, pero avisa del error.
      _replace(emit, silent && column.items.isNotEmpty ? column.copyWith(phase: ColumnPhase.ready, failure: toFailure(error)) : column.copyWith(phase: ColumnPhase.failure, failure: toFailure(error)));
    }
  }
}
