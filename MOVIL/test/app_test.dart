import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/app.dart';
import 'package:mantix/repositories/auth/auth_repository.dart';
import 'package:mantix/bloc/auth/auth_bloc.dart';
import 'package:mantix/services/native_auth_provider.dart';
import 'package:mantix/core/config/app_config.dart';
import 'package:mantix/services/api_client.dart';
import 'package:mantix/repositories/auth/mobile_auth_repository.dart';
import 'package:mantix/repositories/equipment/equipment_repository.dart';
import 'package:mantix/repositories/inventory/inventory_repository.dart';
import 'package:mantix/repositories/profile/profile_repository.dart';
import 'package:mantix/repositories/home/dashboard_repository.dart';
import 'package:mantix/repositories/notifications/notifications_repository.dart';
import 'package:mantix/repositories/catalogs/catalogs_repository.dart';
import 'package:mantix/repositories/queue/queue_repository.dart';
import 'package:mantix/repositories/maintenance/maintenance_repository.dart';
import 'package:mantix/repositories/reports/reports_repository.dart';
import 'package:mantix/repositories/technicians/technicians_repository.dart';
import 'package:mantix/repositories/users/users_repository.dart';
import 'package:mantix/repositories/requests/requests_repository.dart';
import 'package:mantix/repositories/settings/settings_repository.dart';

import 'support/fakes.dart';

const config = AppConfig(apiBaseUrl: 'http://api.test', appVersion: '1.0.0');

Map<String, Object?> me(List<String> roles, List<String> permissions) => {
      'id': 1,
      'email': 'a@b.c',
      'full_name': 'Ana Pérez',
      'employee_code': null,
      'is_active': true,
      'roles': [for (final r in roles) {'code': r, 'name': r}],
      'permissions': [for (final p in permissions) {'code': p, 'name': p}],
    };

/// Monta la app completa con el mismo cableado que `main`, pero con un servidor falso.
Widget appWith({String? token = 'token-0', required Object body, void Function(FakeAdapter adapter)? onAdapter}) {
  final auth = FakeAuthProvider(token: token);
  final adapter = FakeAdapter((_) => jsonResponse(200, body));
  onAdapter?.call(adapter);
  late final AuthBloc authBloc;
  final dio = createApiClient(
    config: config,
    auth: auth,
    adapter: adapter,
    onSessionExpired: () => authBloc.add(const AuthSessionExpired()),
  );
  authBloc = AuthBloc(auth: auth, repository: AuthRepository(dio))..add(const AuthStarted());
  addTearDown(authBloc.close);
  return MantixApp(
    authBloc: authBloc,
    requestsRepository: RequestsRepository(dio),
    catalogsRepository: CatalogsRepository(dio),
    queueRepository: QueueRepository(dio),
    usersRepository: UsersRepository(dio),
    techniciansRepository: TechniciansRepository(dio),
    maintenanceRepository: MaintenanceRepository(dio),
    reportsRepository: ReportsRepository(dio),
    settingsRepository: SettingsRepository(dio),
    mobileAuthRepository: MobileAuthRepository(dio, NativeAuthProvider()),
    dashboardRepository: DashboardRepository(dio),
    equipmentRepository: EquipmentRepository(dio),
    inventoryRepository: InventoryRepository(dio),
    profileRepository: ProfileRepository(dio),
    notificationsRepository: NotificationsRepository(dio),
  );
}

void main() {
  testWidgets('sin sesión muestra el acceso', (tester) async {
    await tester.pumpWidget(appWith(token: null, body: {}));
    await tester.pumpAndSettle();

    expect(find.text('Bienvenido de nuevo'), findsOneWidget);
  });

  testWidgets('cuenta sin roles muestra pendiente de aprobación', (tester) async {
    await tester.pumpWidget(appWith(body: me([], [])));
    await tester.pumpAndSettle();

    expect(find.text('Cuenta pendiente de aprobación'), findsOneWidget);
    expect(find.text('Volver a comprobar'), findsOneWidget);
  });

  testWidgets('cuenta con rol y sin permisos muestra sin acceso asignado', (tester) async {
    await tester.pumpWidget(appWith(body: me(['X'], [])));
    await tester.pumpAndSettle();

    expect(find.text('Sin acceso asignado'), findsOneWidget);
    expect(find.text('Cuenta pendiente de aprobación'), findsNothing);
  });

  testWidgets('técnico aterriza en su bandeja de trabajo', (tester) async {
    await tester.pumpWidget(appWith(body: me(['TECNICO'], ['tickets:ver_asignados'])));
    await tester.pumpAndSettle();

    expect(find.text('Mi bandeja de trabajo'), findsOneWidget);
  });

  testWidgets('cuenta activa sin criterio de inicio aterriza en Perfil con sus permisos', (tester) async {
    await tester.pumpWidget(appWith(body: me(['X'], ['tickets:ver'])));
    await tester.pumpAndSettle();

    expect(find.text('Ana Pérez'), findsWidgets, reason: 'en el encabezado y en «Mis datos»');
    expect(find.textContaining('Mis permisos'), findsNothing, reason: 'el perfil ya no lista los permisos');
  });

  testWidgets('los botones táctiles miden al menos 48 px', (tester) async {
    await tester.pumpWidget(appWith(body: me([], [])));
    await tester.pumpAndSettle();

    final size = tester.getSize(find.widgetWithText(FilledButton, 'Volver a comprobar'));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('cerrar sesión vuelve al acceso', (tester) async {
    await tester.pumpWidget(appWith(body: me(['TECNICO'], ['tickets:ver_asignados'])));
    await tester.pumpAndSettle();

    // La bandeja ya es la pantalla real: cerrar sesión está en el menú lateral.
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Bienvenido de nuevo'), findsOneWidget);
  });
  testWidgets('al iniciar sesión se cargan las notificaciones y sin sesión no se piden', (tester) async {
    late FakeAdapter signedIn;
    await tester.pumpWidget(appWith(body: me(['TECNICO'], ['tickets:ver_asignados']), onAdapter: (a) => signedIn = a));
    await tester.pumpAndSettle();
    expect(signedIn.requests.where((r) => r.path == '/notifications'), isNotEmpty);

    late FakeAdapter signedOut;
    await tester.pumpWidget(appWith(token: null, body: {}, onAdapter: (a) => signedOut = a));
    await tester.pumpAndSettle();
    expect(signedOut.requests.where((r) => r.path == '/notifications'), isEmpty);
  });
}
