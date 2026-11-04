import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session.dart';

/// Permisos efectivos de la sesión actual (vacío si no hay sesión activa).
/// Solo sirven para ocultar o deshabilitar: la autorización real es del backend.
final permissionsProvider = Provider<Set<String>>((ref) {
  final state = ref.watch(sessionProvider).value;
  return state is SignedIn ? state.profile.permissions : const <String>{};
});
