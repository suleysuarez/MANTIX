import 'package:flutter/material.dart';

import 'app.dart';
import 'core/auth/native_auth_provider.dart';
import 'repositories/auth/auth_repository.dart';
import 'core/auth/bloc/auth_bloc.dart';
import 'core/config/app_config.dart';
import 'core/network/api_client.dart';
import 'repositories/auth/mobile_auth_repository.dart';
import 'repositories/home/dashboard_repository.dart';
import 'repositories/requests/requests_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  final auth = NativeAuthProvider();

  late final AuthBloc authBloc;
  final dio = createApiClient(
    config: config,
    auth: auth,
    onSessionExpired: () => authBloc.add(const AuthSessionExpired()),
  );
  authBloc = AuthBloc(auth: auth, repository: AuthRepository(dio))..add(const AuthStarted());

  runApp(MantixApp(
    authBloc: authBloc,
    requestsRepository: RequestsRepository(dio),
    mobileAuthRepository: MobileAuthRepository(dio, auth),
    dashboardRepository: DashboardRepository(dio),
  ));
}
