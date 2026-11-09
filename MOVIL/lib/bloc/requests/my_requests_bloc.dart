import 'dart:async';

import '../../models/page_info.dart';
import '../paged/paged_bloc.dart';
import '../../models/requests/request_models.dart';
import '../../repositories/requests/requests_repository.dart';

/// Mis solicitudes; [status] es el filtro de estado (`null`: todas). Se recarga
/// sola cuando el repositorio avisa de que se creó una solicitud.
class MyRequestsBloc extends PagedBloc<TicketListItem> {
  MyRequestsBloc({required RequestsRepository repository, this.status, super.pageSize}) : _repository = repository {
    _changes = repository.changes.listen((_) => add(const PagedRefreshed()));
  }

  final RequestsRepository _repository;
  final String? status;
  late final StreamSubscription<void> _changes;

  @override
  Future<PagedResult<TicketListItem>> fetch(int page) => _repository.listRequests(page: page, status: status, size: pageSize);

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
