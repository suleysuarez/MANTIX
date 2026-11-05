/// Origen del token de acceso.
///
/// El proveedor de identidad (Clerk) renueva y rota los tokens; la app solo pide
/// el vigente. Así cambiar de proveedor no toca el cliente HTTP ni las pantallas.
abstract class AuthProvider {
  /// Token vigente, o `null` si no hay sesión. Con [forceRefresh] pide uno nuevo.
  Future<String?> accessToken({bool forceRefresh = false});

  Future<void> signOut();

  /// Emite `true`/`false` cuando el proveedor inicia o cierra sesión por su cuenta
  /// (por ejemplo, tras el formulario de Clerk). El `AuthBloc` lo escucha; así no
  /// compite con el estado del SDK ni lo duplica.
  Stream<bool> get signInChanges;
}

/// Marcador hasta conectar el proveedor real: nunca hay sesión.
class UnconfiguredAuthProvider implements AuthProvider {
  const UnconfiguredAuthProvider();

  @override
  Future<String?> accessToken({bool forceRefresh = false}) async => null;

  @override
  Future<void> signOut() async {}

  @override
  Stream<bool> get signInChanges => const Stream.empty();
}
