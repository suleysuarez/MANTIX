part of 'pending_users_bloc.dart';

sealed class PendingUsersEvent {
  const PendingUsersEvent();
}

/// Carga o recarga los pendientes (al abrir, al tirar para refrescar, al reintentar o tras asignar un rol).
class PendingUsersRequested extends PendingUsersEvent {
  const PendingUsersRequested({this.done});

  /// Se completa cuando termina la carga.
  final Completer<void>? done;
}
