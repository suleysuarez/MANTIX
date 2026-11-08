/// Abstracción del almacenamiento y ciclo de vida del token de acceso móvil.
abstract class AuthProvider {
  /// Token vigente, o `null` si no hay sesión. Con [forceRefresh] pide uno nuevo.
  Future<String?> accessToken({bool forceRefresh = false});

  Future<void> signOut();

  /// Emite cuando se guarda o elimina el token; el AuthBloc recarga el perfil.
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
