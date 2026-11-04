import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/auth/auth_provider.dart';
import 'core/auth/clerk_auth_provider.dart';
import 'core/config/app_config.dart';
import 'core/network/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  final clerk = await _startClerk(config);

  runApp(ProviderScope(
    // Riverpod 3 reintenta solo los providers que fallan, con esperas crecientes; la app
    // prefiere mostrar el error enseguida con su botón «Reintentar».
    retry: (_, _) => null,
    overrides: [
      appConfigProvider.overrideWithValue(config),
      clerkAuthStateProvider.overrideWithValue(clerk),
      authProviderProvider.overrideWithValue(
        clerk == null ? const UnconfiguredAuthProvider() : ClerkAuthProvider.fromState(clerk),
      ),
    ],
    child: const MantixApp(),
  ));
}

/// Inicia Clerk. Devuelve `null` si no hay clave o si falla (por ejemplo sin
/// red): la app arranca igual y la pantalla de acceso lo explica.
Future<ClerkAuthState?> _startClerk(AppConfig config) async {
  if (!config.hasClerk) return null;
  try {
    return await ClerkAuthState.create(
      config: ClerkAuthConfig(publishableKey: config.clerkPublishableKey),
    );
  } catch (_) {
    return null;
  }
}
