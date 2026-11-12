import 'dart:async';

import '../paged/paged_bloc.dart';
import '../../models/page_info.dart';
import '../../models/requests/request_models.dart';
import '../../repositories/requests/requests_repository.dart';

/// Bandeja de tickets para los perfiles que tienen permiso de consulta global o asignada.
class TicketsBloc extends PagedBloc<TicketListItem> {
  TicketsBloc({required RequestsRepository repository, this.status, this.search, this.dateFrom, this.dateTo, this.priorities = const [], this.equipmentIds = const [], super.pageSize}) : _repository = repository {
    _changes = repository.changes.listen((_) => add(const PagedRefreshed()));
  }

  final RequestsRepository _repository;
  final String? status;
  final String? search;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final List<String> priorities;
  final List<int> equipmentIds;
  late final StreamSubscription<void> _changes;

  @override
  Future<PagedResult<TicketListItem>> fetch(int page) async {
    Future<PagedResult<TicketListItem>> request(int requestedPage) => _repository.listRequests(
          page: requestedPage,
          status: status,
          search: search,
          dateFrom: dateFrom,
          dateTo: dateTo,
          priorities: priorities,
          equipmentIds: equipmentIds,
          size: pageSize,
        );

    final first = await request(page);
    // Kanban no tiene paginador: consume todas las páginas del servidor en una sola carga.
    if (pageSize < 500 || page != 1 || first.info?.nextPage == null) return first;
    final items = [...first.items];
    var info = first.info;
    while (info?.nextPage != null) {
      final next = await request(info!.nextPage!);
      items.addAll(next.items);
      if (next.info == null) {
        info = null;
        break;
      }
      info = next.info;
    }
    return PagedResult(items: items, info: info);
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
