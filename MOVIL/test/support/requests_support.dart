import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mantix/bloc/auth/auth_bloc.dart';
import 'package:mantix/bloc/auth/permissions_cubit.dart';
import 'package:mantix/bloc/notifications/notifications_bloc.dart';
import 'package:mantix/core/theme/app_theme.dart';
import 'package:mantix/repositories/catalogs/catalogs_repository.dart';
import 'package:mantix/repositories/profile/profile_repository.dart';
import 'package:mantix/services/device_services.dart';
import 'package:mantix/repositories/equipment/equipment_repository.dart';
import 'package:mantix/repositories/queue/queue_repository.dart';
import 'package:mantix/repositories/maintenance/maintenance_repository.dart';
import 'package:mantix/repositories/reports/reports_repository.dart';
import 'package:mantix/repositories/technicians/technicians_repository.dart';
import 'package:mantix/repositories/users/users_repository.dart';
import 'package:mantix/repositories/requests/requests_repository.dart';

import 'fakes.dart';
import 'header_support.dart';

Map<String, Object?> ticketJson({
  int id = 1,
  String status = 'submitted',
  String title = 'La laptop no enciende',
  String priority = 'high',
  bool canAct = false,
  Map<String, Object?>? equipment,
}) =>
    {
      'id': id,
      'ticket_number': 'TCK-000$id',
      'equipment_id': 12,
      'title': title,
      'priority': priority,
      'category': null,
      'status': status,
      'created_at': '2026-11-02T15:30:00Z',
      'can_act': canAct,
      'equipment': ?equipment,
    };

Map<String, Object?> detailJson({int id = 1, String status = 'assigned'}) => {
      'id': id,
      'ticket_number': 'TCK-000$id',
      'equipment': {'id': 12, 'asset_tag': 'EQ-0012', 'brand': 'Dell', 'model': 'Latitude'},
      'requested_by': {'id': 3, 'full_name': 'Ana', 'email': 'ana@x.co'},
      'title': 'La laptop no enciende',
      'description': 'Pantalla negra desde la mañana.',
      'priority': 'high',
      'category': null,
      'status': status,
      'resolution_summary': null,
      'resolved_at': null,
      'closed_at': null,
      'created_at': '2026-11-02T15:30:00Z',
      'updated_at': '2026-11-02T16:00:00Z',
      'current_assignment': {
        'id': 1,
        'technician': {'id': 5, 'user_id': 9, 'full_name': 'Luis Técnico'},
        'assigned_at': '2026-11-02T16:00:00Z',
        'unassigned_at': null,
        'notes': null,
      },
      'status_history': [
        {'id': 1, 'from_status': null, 'to_status': 'submitted', 'changed_at': '2026-11-02T15:30:00Z', 'notes': null},
        {'id': 2, 'from_status': 'submitted', 'to_status': 'assigned', 'changed_at': '2026-11-02T16:00:00Z', 'notes': 'Revisar hoy'},
      ],
      'allowed_next_statuses': <String>[],
    };

Map<String, Object?> equipmentJson({int id = 12, String tag = 'EQ-0012'}) => {
      'id': id,
      'asset_tag': tag,
      'serial_number': 'SN$id',
      'equipment_type_id': 1,
      'equipment_type': {'id': 1, 'code': 'laptop', 'name': 'Laptop'},
      'brand': 'Dell',
      'model': 'Latitude',
      'status': 'assigned',
      'current_custodian': {'id': 77, 'full_name': 'Otra Persona', 'email': 'o@x.co'},
    };

/// Respuesta JSON con cabeceras de paginación del backend.
ResponseBody pagedResponse(List<Object?> items, {int page = 1, int totalPages = 1, int? total}) => ResponseBody.fromString(
      jsonEncode(items),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        'x-total-count': ['${total ?? items.length}'],
        'x-page': ['$page'],
        'x-page-size': ['20'],
        'x-total-pages': ['$totalPages'],
      },
    );

ResponseBody errorResponse(int status, {String? code, List<Map<String, String>>? errors}) => jsonResponse(status, {
      'detail': 'detalle interno que no debe verse',
      'code': code ?? 'error',
      'errors': errors,
      'request_id': 'req-1',
    });

Dio dioWith(FakeAdapter adapter) => Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = adapter;

class MockPermissionsCubit extends MockCubit<PermissionsState> implements PermissionsCubit {}

/// Cubit de permisos de mentira con los permisos indicados.
PermissionsCubit permissionsCubit(Set<String> permissions) {
  final cubit = MockPermissionsCubit();
  whenListen(cubit, const Stream<PermissionsState>.empty(), initialState: PermissionsState(permissions));
  return cubit;
}

/// Monta [screen] con un router mínimo: las rutas a las que navega la pantalla
/// muestran un texto identificable.
Future<GoRouter> pumpScreen(
  WidgetTester tester,
  Widget screen,
  FakeAdapter adapter, {
  Set<String> permissions = const {'solicitudes:ver', 'solicitudes:crear'},
  Size size = const Size(1400, 1800),
  double textScale = 1,
}) async {
  // Pantalla alta y ancha: las listas perezosas construyen todo lo que se prueba.
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/test',
    routes: [
      GoRoute(path: '/test', builder: (_, _) => screen),
      GoRoute(path: '/solicitudes/nueva', builder: (_, _) => const Scaffold(body: Text('pantalla nueva'))),
      GoRoute(
        path: '/solicitudes/:id',
        builder: (_, state) => Scaffold(body: Text('detalle ${state.pathParameters['id']}')),
      ),
      GoRoute(path: '/perfil', builder: (_, _) => const Scaffold(body: Text('pantalla perfil'))),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => RequestsRepository(dioWith(adapter))),
        RepositoryProvider(create: (_) => CatalogsRepository(dioWith(adapter))),
        RepositoryProvider(create: (_) => QueueRepository(dioWith(adapter))),
        RepositoryProvider(create: (_) => UsersRepository(dioWith(adapter))),
        RepositoryProvider(create: (_) => TechniciansRepository(dioWith(adapter))),
        RepositoryProvider(create: (_) => MaintenanceRepository(dioWith(adapter))),
        RepositoryProvider(create: (_) => ReportsRepository(dioWith(adapter))),
        RepositoryProvider(create: (_) => EquipmentRepository(dioWith(adapter))),
        RepositoryProvider(create: (_) => ProfileRepository(dioWith(adapter))),
        RepositoryProvider(create: (_) => DeviceServices()),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: permissionsCubit(permissions)),
          BlocProvider<AuthBloc>.value(value: authenticatedBloc(testProfile(permissions: permissions))),
          BlocProvider<NotificationsBloc>.value(value: notificationsBloc()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          builder: (context, app) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: app!),
        ),
      ),
    ),
  );
  return router;
}
