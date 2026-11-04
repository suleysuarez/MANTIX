import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';

/// Estado de Clerk ya inicializado, o `null` si no hay clave o falló el arranque.
/// Se sobrescribe en `main` una vez creado.
final clerkAuthStateProvider = Provider<ClerkAuthState?>((_) => null);

/// Entrega al cliente HTTP el token de sesión que gestiona Clerk.
///
/// Clerk renueva y rota los tokens; aquí solo se pide el vigente. Las cuatro
/// operaciones llegan como funciones para poder probar esta clase sin el SDK.
class ClerkAuthProvider implements AuthProvider {
  ClerkAuthProvider({
    required this._isSignedIn,
    required this._jwt,
    required this._refresh,
    required this._signOut,
  });

  factory ClerkAuthProvider.fromState(ClerkAuthState state) => ClerkAuthProvider(
        isSignedIn: () => state.isSignedIn,
        jwt: () async => (await state.sessionToken()).jwt,
        refresh: state.refreshClient,
        signOut: state.signOut,
      );

  final bool Function() _isSignedIn;
  final Future<String> Function() _jwt;
  final Future<void> Function() _refresh;
  final Future<void> Function() _signOut;

  @override
  Future<String?> accessToken({bool forceRefresh = false}) async {
    if (!_isSignedIn()) return null;
    try {
      if (forceRefresh) await _refresh();
      return await _jwt();
    } catch (_) {
      // Sin token utilizable la petición sale sin Authorization y el servidor
      // responde 401: la app lo trata como sesión caducada, sin filtrar el motivo.
      return null;
    }
  }

  @override
  Future<void> signOut() => _signOut();
}
