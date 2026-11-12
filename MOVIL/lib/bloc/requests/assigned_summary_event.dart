part of 'assigned_summary_bloc.dart';

sealed class AssignedSummaryEvent {
  const AssignedSummaryEvent();
}

/// Pide las cifras (al abrir, al tirar para refrescar, al reintentar o cuando algo cambia).
class AssignedSummaryRequested extends AssignedSummaryEvent {
  const AssignedSummaryRequested({this.done});

  /// Se completa al terminar (tirar para refrescar espera a esto).
  final Completer<void>? done;
}
