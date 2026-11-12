part of 'users_list_bloc.dart';

sealed class UsersListEvent {
  const UsersListEvent();
}

/// Primera carga (página 1).
class UsersListStarted extends UsersListEvent {
  const UsersListStarted();
}

/// Cambia de página (base 1).
class UsersPageSelected extends UsersListEvent {
  const UsersPageSelected(this.page);

  final int page;
}

/// Vuelve a pedir la página actual; con datos cargados se siguen mostrando.
class UsersListRefreshed extends UsersListEvent {
  const UsersListRefreshed({this.done});

  /// Se completa al terminar; el «tirar para refrescar» espera a que acabe.
  final Completer<void>? done;
}
