part of 'users_summary_bloc.dart';

sealed class UsersSummaryEvent {
  const UsersSummaryEvent();
}

/// Carga o recarga el resumen (al abrir, al tirar para refrescar, al reintentar o tras un cambio).
class UsersSummaryRequested extends UsersSummaryEvent {
  const UsersSummaryRequested({this.done});

  /// Se completa cuando termina la carga (tirar para refrescar espera a esto).
  final Completer<void>? done;
}
