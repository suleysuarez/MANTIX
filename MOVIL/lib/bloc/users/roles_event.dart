part of 'roles_bloc.dart';

sealed class RolesEvent {
  const RolesEvent();
}

/// Carga o recarga los roles (al abrir, al tirar para refrescar, al reintentar o tras un cambio).
class RolesRequested extends RolesEvent {
  const RolesRequested({this.done});

  /// Se completa cuando termina la carga.
  final Completer<void>? done;
}
