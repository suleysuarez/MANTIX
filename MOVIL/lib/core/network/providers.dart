import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import '../config/app_config.dart';
import 'api_client.dart';

final appConfigProvider = Provider<AppConfig>((_) => AppConfig.fromEnvironment());

/// Se sobrescribe cuando se conecte el proveedor de identidad real.
final authProviderProvider = Provider<AuthProvider>((_) => const UnconfiguredAuthProvider());

final apiClientProvider = Provider<Dio>((ref) => createApiClient(
      config: ref.watch(appConfigProvider),
      auth: ref.watch(authProviderProvider),
    ));
