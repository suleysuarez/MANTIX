/// Origen del token de acceso.
///
/// El proveedor de identidad (Clerk, a confirmar en la Fase 0.5) renueva y rota
/// los tokens; la app solo pide el vigente. Así cambiar de proveedor no toca
/// el cliente HTTP ni las pantallas.
abstract class AuthProvider {
  /// Token vigente, o `null` si no hay sesión. Con [forceRefresh] pide uno nuevo.
  Future<String?> accessToken({bool forceRefresh = false});

  Future<void> signOut();
}

/// Marcador hasta conectar el proveedor real: nunca hay sesión.
class UnconfiguredAuthProvider implements AuthProvider {
  const UnconfiguredAuthProvider();

  @override
  Future<String?> accessToken({bool forceRefresh = false}) async => null;

  @override
  Future<void> signOut() async {}
}
