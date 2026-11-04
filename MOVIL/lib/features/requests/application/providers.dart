import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/page_info.dart';
import '../../../core/network/paged_notifier.dart';
import '../data/models.dart';
import '../data/requests_repository.dart';

/// Mis solicitudes; el argumento es el filtro de estado (`null`: todas).
class MyRequestsNotifier extends PagedNotifier<TicketListItem> {
  MyRequestsNotifier(this.status);

  final String? status;

  @override
  Future<PagedResult<TicketListItem>> fetch(int page) =>
      ref.read(requestsRepositoryProvider).listRequests(page: page, status: status);
}

final myRequestsProvider = AsyncNotifierProvider.autoDispose
    .family<MyRequestsNotifier, PagedState<TicketListItem>, String?>(MyRequestsNotifier.new);

/// Resultados del selector de equipo; el argumento es el texto buscado.
class EquipmentSearchNotifier extends PagedNotifier<EquipmentOption> {
  EquipmentSearchNotifier(this.search);

  final String search;

  @override
  Future<PagedResult<EquipmentOption>> fetch(int page) =>
      ref.read(requestsRepositoryProvider).searchEquipment(search: search, page: page);
}

final equipmentSearchProvider = AsyncNotifierProvider.autoDispose
    .family<EquipmentSearchNotifier, PagedState<EquipmentOption>, String>(EquipmentSearchNotifier.new);

final requestDetailProvider = FutureProvider.autoDispose.family<TicketDetail, int>(
  (ref, id) => ref.watch(requestsRepositoryProvider).getRequest(id),
);

final requestAttachmentsProvider = FutureProvider.autoDispose.family<List<Attachment>, int>(
  (ref, id) => ref.watch(requestsRepositoryProvider).listAttachments(id),
);
