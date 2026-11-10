import 'package:flutter/material.dart';

import 'core/app.dart';
import 'services/native_auth_provider.dart';
import 'repositories/auth/auth_repository.dart';
import 'bloc/auth/auth_bloc.dart';
import 'core/config/app_config.dart';
import 'services/api_client.dart';
import 'repositories/auth/mobile_auth_repository.dart';
import 'repositories/equipment/equipment_repository.dart';
import 'repositories/home/dashboard_repository.dart';
import 'repositories/users/users_repository.dart';
import 'repositories/queue/queue_repository.dart';
import 'repositories/notifications/notifications_repository.dart';
import 'repositories/catalogs/catalogs_repository.dart';
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
    catalogsRepository: CatalogsRepository(dio),
    mobileAuthRepository: MobileAuthRepository(dio, auth),
    dashboardRepository: DashboardRepository(dio),
    equipmentRepository: EquipmentRepository(dio),
    notificationsRepository: NotificationsRepository(dio),
    queueRepository: QueueRepository(dio),
    usersRepository: UsersRepository(dio),
  ));
}
