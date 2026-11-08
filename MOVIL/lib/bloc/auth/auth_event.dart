part of 'auth_bloc.dart';

sealed class AuthEvent {
  const AuthEvent();
}

/// Primera comprobación al abrir la app: ¿hay sesión y qué perfil tiene?
class AuthStarted extends AuthEvent {
  const AuthStarted();
}

/// Vuelve a cargar el perfil (tras iniciar sesión o al pulsar «Volver a comprobar»).
class AuthRefreshRequested extends AuthEvent {
  const AuthRefreshRequested();
}

class AuthSignOutRequested extends AuthEvent {
  const AuthSignOutRequested();
}

/// El servidor siguió respondiendo 401 tras la única renovación del token.
class AuthSessionExpired extends AuthEvent {
  const AuthSessionExpired();
}
