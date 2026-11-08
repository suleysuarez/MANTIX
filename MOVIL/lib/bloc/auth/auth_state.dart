part of 'auth_bloc.dart';

/// Estado de la sesión de la app. Nunca guarda tokens: solo el perfil local.
sealed class AuthState extends Equatable {
  const AuthState();

  /// Perfil cargado; `null` si no hay sesión utilizable.
  UserProfile? get profile => null;

  @override
  List<Object?> get props => [];
}

/// Aún no se sabe: se está cargando el perfil.
class AuthUnknown extends AuthState {
  const AuthUnknown();
}

/// Sin sesión, o sesión que el servidor ya no acepta ([failure] explica por qué).
class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({this.failure});

  final Failure? failure;

  @override
  List<Object?> get props => [failure];
}

/// Hay token pero no se pudo cargar el perfil (red o servidor): se puede reintentar.
class AuthUnavailable extends AuthState {
  const AuthUnavailable(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

/// Cuenta sin ningún rol: espera aprobación de un administrador.
class AuthPending extends AuthState {
  const AuthPending(this.profile);

  @override
  final UserProfile profile;

  @override
  List<Object?> get props => [profile];
}

/// Cuenta con roles pero sin ningún permiso.
class AuthNoAccess extends AuthState {
  const AuthNoAccess(this.profile);

  @override
  final UserProfile profile;

  @override
  List<Object?> get props => [profile];
}

/// Sesión válida con permisos: la app se usa según [profile].
class Authenticated extends AuthState {
  const Authenticated(this.profile);

  @override
  final UserProfile profile;

  @override
  List<Object?> get props => [profile];
}
