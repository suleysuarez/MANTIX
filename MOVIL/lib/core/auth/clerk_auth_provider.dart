import 'dart:async';

import 'package:clerk_flutter/clerk_flutter.dart';

import 'auth_provider.dart';

/// Entrega al cliente HTTP el token de sesión que gestiona Clerk.
///
/// Clerk renueva y rota los tokens; aquí solo se pide el vigente. Las operaciones
/// llegan como funciones para poder probar esta clase sin el SDK.
class ClerkAuthProvider implements AuthProvider {
  ClerkAuthProvider({
    required this._isSignedIn,
    required this._jwt,
    required this._refresh,
    required this._signOut,
    this._signInChanges = const Stream.empty(),
  });

  factory ClerkAuthProvider.fromState(ClerkAuthState state) => ClerkAuthProvider(
        isSignedIn: () => state.isSignedIn,
        jwt: () async => (await state.sessionToken()).jwt,
        refresh: state.refreshClient,
        signOut: state.signOut,
        signInChanges: _signInChangesOf(state),
      );

  /// Convierte los avisos del `ChangeNotifier` de Clerk en un flujo que solo
  /// emite cuando cambia el hecho de tener la sesión iniciada.
  static Stream<bool> _signInChangesOf(ClerkAuthState state) {
    late final StreamController<bool> controller;
    var wasSignedIn = state.isSignedIn;
    void onChange() {
      if (state.isSignedIn == wasSignedIn) return;
      wasSignedIn = state.isSignedIn;
      controller.add(wasSignedIn);
    }

    controller = StreamController<bool>.broadcast(
      onListen: () => state.addListener(onChange),
      onCancel: () => state.removeListener(onChange),
    );
    return controller.stream;
  }

  final bool Function() _isSignedIn;
  final Future<String> Function() _jwt;
  final Future<void> Function() _refresh;
  final Future<void> Function() _signOut;
  final Stream<bool> _signInChanges;

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

  @override
  Stream<bool> get signInChanges => _signInChanges;
}
