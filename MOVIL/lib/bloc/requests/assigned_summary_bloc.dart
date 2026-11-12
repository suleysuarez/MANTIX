import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/page_info.dart';
import '../../models/requests/request_models.dart';
import '../../repositories/requests/requests_repository.dart';
import 'assigned_tickets_bloc.dart';

part 'assigned_summary_event.dart';
part 'assigned_summary_state.dart';

/// Las cifras del panel del técnico: tickets abiertos, en proceso y urgentes. Cada una es el total
/// que informa el servidor (`X-Total-Count`) de una consulta de un solo ticket, así que son exactas
/// aunque el listado muestre solo los primeros. Se recarga solo cuando algo cambia.
class AssignedSummaryBloc extends Bloc<AssignedSummaryEvent, AssignedSummaryState> {
  AssignedSummaryBloc({required RequestsRepository repository}) : _repository = repository, super(const AssignedSummaryState()) {
    on<AssignedSummaryRequested>(_onRequested);
    _changes = repository.changes.listen((_) => add(const AssignedSummaryRequested()));
  }

  final RequestsRepository _repository;
  late final StreamSubscription<void> _changes;

  Future<int> _total(Future<PagedResult<TicketListItem>> Function() query) async {
    final result = await query();
    return result.info?.total ?? result.items.length;
  }

  Future<void> _onRequested(AssignedSummaryRequested event, Emitter<AssignedSummaryState> emit) async {
    // Al recargar se conservan las cifras que ya se ven; solo cambia lo que llega.
    emit(AssignedSummaryState(status: AssignedSummaryStatus.loading, open: state.open, inProgress: state.inProgress, urgent: state.urgent));
    try {
      final open = AssignedTicketsBloc.openStatuses;
      final totals = await Future.wait([
        _total(() => _repository.listRequests(status: open, size: 1)),
        _total(() => _repository.listRequests(status: 'in_progress', size: 1)),
        _total(() => _repository.listRequests(status: open, priorities: const ['critical', 'high'], size: 1)),
      ]);
      emit(AssignedSummaryState(status: AssignedSummaryStatus.ready, open: totals[0], inProgress: totals[1], urgent: totals[2]));
    } catch (error) {
      emit(AssignedSummaryState(status: AssignedSummaryStatus.failure, open: state.open, inProgress: state.inProgress, urgent: state.urgent, failure: toFailure(error)));
    } finally {
      event.done?.complete();
    }
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
