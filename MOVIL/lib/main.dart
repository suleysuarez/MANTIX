import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/auth/auth_provider.dart';
import 'core/auth/auth_repository.dart';
import 'core/auth/bloc/auth_bloc.dart';
import 'core/auth/clerk_auth_provider.dart';
import 'core/config/app_config.dart';
import 'core/network/api_client.dart';
import 'features/requests/data/requests_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  final clerk = await _startClerk(config);
  final AuthProvider auth = clerk == null ? const UnconfiguredAuthProvider() : ClerkAuthProvider.fromState(clerk);

  // El cliente HTTP avisa al AuthBloc cuando la sesión expira; el Bloc se crea después
  // con ese mismo cliente, por eso el callback usa una variable tardía.
  late final AuthBloc authBloc;
  final dio = createApiClient(
    config: config,
    auth: auth,
    onSessionExpired: () => authBloc.add(const AuthSessionExpired()),
  );
  authBloc = AuthBloc(auth: auth, repository: AuthRepository(dio))..add(const AuthStarted());

  runApp(MantixApp(authBloc: authBloc, requestsRepository: RequestsRepository(dio), clerk: clerk));
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
