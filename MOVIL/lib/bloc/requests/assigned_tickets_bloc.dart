import 'dart:async';

import '../../models/page_info.dart';
import '../../models/requests/request_models.dart';
import '../../repositories/requests/requests_repository.dart';
import '../paged/paged_bloc.dart';

/// Los tickets abiertos que el servidor deja ver a quien trabaja con `tickets:ver_asignados`: lo que
/// tiene asignado, sin lo ya resuelto, cerrado o cancelado. Se recarga solo cuando algo cambia.
class AssignedTicketsBloc extends PagedBloc<TicketListItem> {
  AssignedTicketsBloc({required RequestsRepository repository, super.pageSize}) : _repository = repository {
    _changes = repository.changes.listen((_) => add(const PagedRefreshed()));
  }

  /// Los estados en los que un ticket sigue en manos del técnico (lista separada por comas, como la entiende el servidor).
  static const openStatuses = 'assigned,in_progress,waiting';

  final RequestsRepository _repository;
  late final StreamSubscription<void> _changes;

  @override
  Future<PagedResult<TicketListItem>> fetch(int page) => _repository.listRequests(page: page, status: openStatuses, size: pageSize);

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
