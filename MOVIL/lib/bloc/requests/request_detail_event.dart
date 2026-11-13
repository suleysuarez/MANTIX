part of 'request_detail_bloc.dart';

sealed class RequestDetailEvent {
  const RequestDetailEvent();
}

/// Carga (o recarga, o reintenta) los datos del ticket.
class RequestDetailRequested extends RequestDetailEvent {
  const RequestDetailRequested({this.done});

  /// Se completa al terminar; el «tirar para refrescar» espera a que acabe.
  final Completer<void>? done;
}

/// Carga (o recarga, o reintenta) la lista de adjuntos.
class RequestAttachmentsRequested extends RequestDetailEvent {
  const RequestAttachmentsRequested();
}

/// Carga el flujo de estados (a cuáles puede pasar el ticket y qué datos pide cada uno). Solo se
/// pide cuando el detalle ofrece acciones.
class RequestWorkflowRequested extends RequestDetailEvent {
  const RequestWorkflowRequested();
}

/// Pasa el ticket a [target]. [resolutionSummary] es cómo se resolvió (lo exige «Resuelto») y
/// [notes] una nota opcional del cambio.
class RequestStatusChangeRequested extends RequestDetailEvent {
  const RequestStatusChangeRequested(this.target, {this.notes, this.resolutionSummary});

  final String target;
  final String? notes;
  final String? resolutionSummary;
}
