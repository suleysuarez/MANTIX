import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/auth/auth_bloc.dart';
import 'package:mantix/core/theme/app_theme.dart';
import 'package:mantix/models/auth/user_profile.dart';
import 'package:mantix/pages/equipment/equipment_screen.dart';
import 'package:mantix/repositories/equipment/equipment_repository.dart';

import '../../models/equipment/equipment_models_test.dart' show equipmentItemJson;
import '../../support/fakes.dart';
import '../../support/requests_support.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

const _summaryJson = {
  'total': 38,
  'by_status': {'assigned': 20, 'in_storage': 11, 'in_repair': 3, 'lost': 1, 'retired': 2, 'disposed': 1},
};

UserProfile _profile() => const UserProfile(
      id: 1,
      email: 'ana@mantix.test',
      fullName: 'Ana Pérez',
      isActive: true,
      roles: ['ADMIN'],
      permissions: {'equipos:ver', 'equipos:crear'},
    );

final _laptop = equipmentItemJson();
final _printer = equipmentItemJson(overrides: {
  'id': 8,
  'asset_tag': 'DEMO-008',
  'brand': 'HP',
  'model': 'LaserJet Pro',
  'status': 'in_repair',
  'equipment_type': {'id': 2, 'code': 'PRINTER', 'name': 'Impresora'},
  'current_location': null,
  'current_custodian': null,
  'last_maintenance': null,
});

void main() {
  late _MockAuthBloc authBloc;
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) listHandler;
  late ResponseBody Function(RequestOptions) summaryHandler;

  setUp(() {
    authBloc = _MockAuthBloc();
    listHandler = (_) => pagedResponse([_laptop, _printer]);
    summaryHandler = (_) => jsonResponse(200, _summaryJson);
    adapter = FakeAdapter((options) => options.path == '/equipment/summary' ? summaryHandler(options) : listHandler(options));
  });

  Future<void> pumpScreen(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(390, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    whenListen(authBloc, const Stream<AuthState>.empty(), initialState: Authenticated(_profile()));
    await tester.pumpWidget(
      RepositoryProvider<EquipmentRepository>.value(
        value: EquipmentRepository(dioWith(adapter)),
        child: BlocProvider<AuthBloc>.value(
          value: authBloc,
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, app) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
              child: app!,
            ),
            home: const EquipmentScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<RequestOptions> listRequests() => adapter.requests.where((r) => r.path == '/equipment').toList();

  testWidgets('muestra el título, la descripción y los cuatro contadores', (tester) async {
    await pumpScreen(tester);

    expect(find.text('GESTIÓN DE EQUIPOS'), findsOneWidget);
    expect(find.textContaining('Administra los equipos tecnológicos'), findsOneWidget);
    for (final value in ['38', '31', '3', '4']) {
      expect(find.text(value), findsOneWidget, reason: value);
    }
    for (final badge in ['Total', '81,6% tasa', 'En curso', 'Crítico']) {
      expect(find.text(badge), findsOneWidget, reason: badge);
    }
    for (final action in ['Ver todo', 'Filtrar operativos', 'Ver equipos en mantenimiento', 'Revisar estos equipos']) {
      expect(find.text(action), findsOneWidget, reason: action);
    }
  });

  testWidgets('lista los equipos con estado, categoría, ubicación y custodio', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Dell Latitude 5420'), findsOneWidget);
    expect(find.text('DEMO-007'), findsOneWidget);
    expect(find.text('Asignado'), findsOneWidget);
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Sede central'), findsOneWidget);
    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.textContaining('Último mantenimiento: 20 oct 2026'), findsOneWidget);

    expect(find.text('HP LaserJet Pro'), findsOneWidget);
    expect(find.text('En mantenimiento'), findsOneWidget);
    expect(find.text('Sin ubicación'), findsOneWidget);
    expect(find.text('Sin custodio'), findsOneWidget);
    expect(find.text('Sin mantenimientos'), findsOneWidget);
    expect(find.text('2 equipos'), findsOneWidget);
  });

  testWidgets('la primera carga pide todo el catálogo sin filtros', (tester) async {
    await pumpScreen(tester);

    final request = listRequests().single;
    expect(request.queryParameters.keys, isNot(contains('status')));
    expect(request.queryParameters.keys, isNot(contains('search')));
  });

  testWidgets('tocar una tarjeta filtra el listado por sus estados', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Filtrar operativos'));
    await tester.pumpAndSettle();
    expect(listRequests().last.queryParameters['status'], 'assigned,in_storage');

    await tester.tap(find.text('Ver equipos en mantenimiento'));
    await tester.pumpAndSettle();
    expect(listRequests().last.queryParameters['status'], 'in_repair');

    await tester.tap(find.text('Revisar estos equipos'));
    await tester.pumpAndSettle();
    expect(listRequests().last.queryParameters['status'], 'lost,retired,disposed');

    await tester.tap(find.text('Ver todo'));
    await tester.pumpAndSettle();
    expect(listRequests().last.queryParameters.keys, isNot(contains('status')));
  });

  testWidgets('filtrar no vuelve a pedir los contadores', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Filtrar operativos'));
    await tester.pumpAndSettle();

    expect(adapter.requests.where((r) => r.path == '/equipment/summary'), hasLength(1));
  });

  testWidgets('la búsqueda espera a que dejes de escribir y conserva el texto y el foco', (tester) async {
    await pumpScreen(tester);
    final before = listRequests().length;

    await tester.enterText(find.byType(TextField), '  dell ');
    await tester.pump(const Duration(milliseconds: 100));
    expect(listRequests(), hasLength(before), reason: 'todavía no ha pasado la espera');

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(listRequests().last.queryParameters['search'], 'dell');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '  dell ');
    expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
  });

  testWidgets('enviar la búsqueda la aplica de inmediato', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'LT-0042');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(listRequests().last.queryParameters['search'], 'LT-0042');
  });

  testWidgets('sin resultados muestra el vacío filtrado y permite volver a todo el catálogo', (tester) async {
    listHandler = (options) => pagedResponse(options.queryParameters.containsKey('search') ? [] : [_laptop]);
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Ningún equipo coincide con los filtros'), findsOneWidget);
    expect(find.text('GESTIÓN DE EQUIPOS'), findsOneWidget, reason: 'el encabezado sigue visible');

    await tester.tap(find.text('Ver todo el catálogo'));
    await tester.pumpAndSettle();

    expect(find.text('Dell Latitude 5420'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });

  testWidgets('sin ningún equipo registrado lo dice', (tester) async {
    listHandler = (_) => pagedResponse([]);
    await pumpScreen(tester);

    expect(find.text('Aún no hay equipos registrados'), findsOneWidget);
    expect(find.text('Ver todo el catálogo'), findsNothing);
  });

  testWidgets('si el listado falla muestra el error con reintento y el encabezado', (tester) async {
    listHandler = (_) => errorResponse(500);
    await pumpScreen(tester);

    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('GESTIÓN DE EQUIPOS'), findsOneWidget);
    expect(find.textContaining('detalle interno'), findsNothing);

    listHandler = (_) => pagedResponse([_laptop]);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.text('Dell Latitude 5420'), findsOneWidget);
  });

  testWidgets('si los contadores fallan se muestran con guion y se pueden reintentar', (tester) async {
    summaryHandler = (_) => errorResponse(500);
    await pumpScreen(tester);

    expect(find.text('–'), findsNWidgets(4));
    expect(find.textContaining('No pudimos cargar los contadores'), findsOneWidget);
    expect(find.text('Dell Latitude 5420'), findsOneWidget, reason: 'el listado no depende de los contadores');

    summaryHandler = (_) => jsonResponse(200, _summaryJson);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.text('38'), findsOneWidget);
  });

  testWidgets('el menú lateral ofrece Equipos con el permiso equipos:ver', (tester) async {
    await pumpScreen(tester);

    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();

    expect(find.text('Equipos'), findsOneWidget);
  });

  testWidgets('con la fuente del sistema más grande no se desborda', (tester) async {
    await pumpScreen(tester, textScale: 1.3);

    expect(tester.takeException(), isNull);
    expect(find.text('Dell Latitude 5420'), findsOneWidget);
  });
}
