import 'dart:async';

import '../paged/paged_bloc.dart';
import '../../models/page_info.dart';
import '../../models/requests/request_models.dart';
import '../../repositories/requests/requests_repository.dart';

/// Bandeja de tickets para los perfiles que tienen permiso de consulta global o asignada.
class TicketsBloc extends PagedBloc<TicketListItem> {
  TicketsBloc({required RequestsRepository repository, this.status, this.search}) : _repository = repository {
    _changes = repository.changes.listen((_) => add(const PagedRefreshed()));
  }

  final RequestsRepository _repository;
  final String? status;
  final String? search;
  late final StreamSubscription<void> _changes;

  @override
  Future<PagedResult<TicketListItem>> fetch(int page) =>
      _repository.listRequests(page: page, status: status, search: search);

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
