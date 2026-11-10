import 'package:equatable/equatable.dart';

import '../requests/request_models.dart';

/// El flujo de estados que entrega el servidor (`/maintenance/requests/workflow`) visto desde la
/// bandeja de triaje: qué estados son columnas y qué movimientos son válidos. Ninguna transición
/// está escrita en la app.
class QueueWorkflow extends Equatable {
  const QueueWorkflow([this.states = const []]);

  final List<WorkflowStatus> states;

  WorkflowStatus? of(String status) => states.where((state) => state.status == status).firstOrNull;

  /// Estados que esperan trabajo (`in_queue`), en el orden del flujo.
  List<WorkflowStatus> get columns => [for (final state in states) if (state.inQueue) state]..sort((a, b) => a.order.compareTo(b.order));

  bool isColumn(String status) => of(status)?.inQueue ?? false;

  /// Datos que exige entrar en [target]: `category`, `priority`, `technician`, `reason`…
  List<String> requiresFor(String target) => of(target)?.requires ?? const [];

  /// ¿Se puede mover [ticket] a [target]? Debe poder actuar sobre él, la transición debe existir
  /// y quien llama debe poder entrar en el destino.
  bool canMove(TicketListItem ticket, String target) {
    if (!ticket.canAct || ticket.status == target) return false;
    final from = of(ticket.status);
    final to = of(target);
    return from != null && to != null && from.allowedTargets.contains(target) && to.canEnter;
  }

  /// Destinos válidos de [ticket], en el orden del flujo.
  List<String> targetsFor(TicketListItem ticket) => [for (final state in states) if (canMove(ticket, state.status)) state.status];

  /// Por qué NO se puede mover por falta de permiso (para decirlo en vez de «paso inválido»), o
  /// `null` si no es por eso.
  String? permissionBlock(TicketListItem ticket, String target, {required String Function(String status) label}) {
    if (!ticket.canAct) return 'Solo puedes mover las solicitudes sobre las que tienes permiso.';
    if (of(target)?.canEnter == false) return 'Tu rol no puede pasar solicitudes a «${label(target)}».';
    return null;
  }

  @override
  List<Object?> get props => [states];
}
