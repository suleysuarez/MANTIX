part of 'queue_summary_bloc.dart';

sealed class QueueSummaryEvent extends Equatable {
  const QueueSummaryEvent();

  @override
  List<Object?> get props => [];
}

/// Carga o recarga el resumen (al abrir, al tirar para refrescar, tras mover una tarjeta o al reintentar).
class QueueSummaryRequested extends QueueSummaryEvent {
  const QueueSummaryRequested({this.done});

  /// Se completa cuando termina la carga (tirar para refrescar espera a esto).
  final Completer<void>? done;
}
