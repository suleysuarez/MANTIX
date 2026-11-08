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
