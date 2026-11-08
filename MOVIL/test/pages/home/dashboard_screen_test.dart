import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/auth/auth_bloc.dart';
import 'package:mantix/core/routing/home_resolver.dart';
import 'package:mantix/core/theme/app_theme.dart';
import 'package:mantix/models/auth/user_profile.dart';
import 'package:mantix/pages/home/dashboard_screen.dart';
import 'package:mantix/repositories/home/dashboard_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _MockDashboardRepository extends Mock implements DashboardRepository {}

UserProfile profile({List<String> permissions = const ['dashboard:ver_todos', 'tickets:ver_todos', 'tecnicos:ver', 'equipos:ver']}) => UserProfile.fromJson({
  'id': 1,
  'email': 'ana@mantix.test',
  'full_name': 'Ana Pérez',
  'employee_code': null,
  'is_active': true,
  'roles': [
    {'code': 'ADMIN', 'name': 'Administrador'},
  ],
  'permissions': [for (final p in permissions) {'code': p, 'name': p}],
});

const kpis = {
  'mttr_hours': {'value': 62.4, 'previous': 51.6, 'change_pct': 20.9, 'sample_size': 42, 'low_sample': false},
  'first_assignment_hours': {'value': 36.8, 'previous': null, 'change_pct': null, 'sample_size': 42, 'low_sample': false},
  'sla_compliance_pct': {'value': 54.8, 'previous': 58.3, 'change_pct': -6.0, 'sample_size': 42, 'low_sample': false, 'met': 23, 'missed': 19},
  'backlog': {'open': 10, 'previous_open': 8, 'change_pct': 25.0},
  'availability': {'value': 81.6, 'previous': 80.6, 'change_pct': 1.2, 'operational': 31, 'total': 38},
};

const trends = {
  'points': [
    {'bucket': '2026-10-01T00:00:00Z', 'created': 3, 'resolved': 1, 'mttr_hours': 40.0, 'sla_compliance_pct': 50.0},
    {'bucket': '2026-10-02T00:00:00Z', 'created': 2, 'resolved': 4, 'mttr_hours': 55.0, 'sla_compliance_pct': 60.0},
    {'bucket': '2026-10-03T00:00:00Z', 'created': 5, 'resolved': 2, 'mttr_hours': 70.0, 'sla_compliance_pct': 45.0},
  ],
};

const alerts = {
  'tickets': [
    {'id': 1, 'ticket_number': 'DEMO-T-0042', 'title': 'No puede iniciar sesión', 'equipment_id': 16, 'asset_tag': 'DEMO-016', 'priority': 'critical', 'status': 'submitted', 'assigned': false, 'sla_deadline': '2026-10-08T12:00:00Z', 'reason': 'sla_breached'},
  ],
  'down_equipment': [],
  'schedules': [],
};

const technicians = {
  'technicians': [
    {'technician_id': 1, 'full_name': 'Luis Demo', 'specialization': 'Hardware', 'is_available': true, 'open_tickets': 3, 'resolved': 18, 'mttr_median_hours': 67.2, 'sample_size': 18, 'low_sample': false, 'sla_compliance_pct': 55.6, 'sla_sample_size': 18, 'sla_low_sample': false, 'sla_excluded_no_sla': 0, 'reopened': 0},
    {'technician_id': 3, 'full_name': 'Marta Demo', 'specialization': 'Software', 'is_available': false, 'open_tickets': 0, 'resolved': 2, 'mttr_median_hours': 91.2, 'sample_size': 2, 'low_sample': true, 'sla_compliance_pct': 50.0, 'sla_sample_size': 2, 'sla_low_sample': true, 'sla_excluded_no_sla': 0, 'reopened': 0},
  ],
};

const equipment = {
  'equipment': [
    {'equipment_id': 1, 'asset_tag': 'DEMO-001', 'brand': 'Dell', 'model': 'Latitude 5420', 'tickets': 5},
    {'equipment_id': 2, 'asset_tag': 'DEMO-011', 'brand': 'Dell', 'model': 'Latitude 5420', 'tickets': 4},
  ],
};

void main() {
  late _MockAuthBloc authBloc;
  late _MockDashboardRepository repository;

  setUp(() {
    authBloc = _MockAuthBloc();
    repository = _MockDashboardRepository();
    when(() => repository.loadKpis(any())).thenAnswer((_) async => Map<String, dynamic>.from(kpis));
    when(() => repository.loadTrends(any())).thenAnswer((_) async => Map<String, dynamic>.from(trends));
    when(() => repository.loadAlerts()).thenAnswer((_) async => Map<String, dynamic>.from(alerts));
    when(() => repository.loadTechnicians(any())).thenAnswer((_) async => Map<String, dynamic>.from(technicians));
    when(() => repository.loadTopEquipment(any())).thenAnswer((_) async => Map<String, dynamic>.from(equipment));
  });

  Future<void> pumpDashboard(WidgetTester tester, {double textScale = 1, UserProfile? user}) async {
    tester.view.physicalSize = const Size(360, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    whenListen(authBloc, const Stream<AuthState>.empty(), initialState: Authenticated(user ?? profile()));
    await tester.pumpWidget(
      RepositoryProvider<DashboardRepository>.value(
        value: repository,
        child: BlocProvider<AuthBloc>.value(
          value: authBloc,
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, app) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
              child: app!,
            ),
            home: const DashboardScreen(destination: HomeDestination.globalDashboard),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder assetImage(String name) => find.byWidgetPredicate((widget) {
    if (widget is! Image) return false;
    final provider = widget.image;
    final inner = provider is ResizeImage ? provider.imageProvider : provider;
    return inner is AssetImage && inner.assetName == name;
  });

  testWidgets('el encabezado muestra solo la M, a la izquierda, y la tarjeta de bienvenida usa la imagen del panel', (tester) async {
    await pumpDashboard(tester);

    expect(assetImage('assets/images/mantix_m.webp'), findsOneWidget);
    expect(assetImage('assets/images/mantix_wordmark.webp'), findsNothing, reason: 'el logo completo solo va en el panel lateral');
    expect(tester.getCenter(assetImage('assets/images/mantix_m.webp')).dx, lessThan(120), reason: 'la M va a la izquierda, junto al botón del menú');
    expect(assetImage('assets/images/card_dashboard.png'), findsOneWidget);
    expect(find.text('HOLA, ANA'), findsOneWidget);
    expect(find.text('Sistema Inteligente\nde Mantenimiento'), findsOneWidget);
    expect(find.textContaining('control en tiempo real del parque tecnológico empresarial'), findsOneWidget);
  });

  testWidgets('el panel lateral lleva el logo completo', (tester) async {
    await pumpDashboard(tester);

    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();

    expect(assetImage('assets/images/mantix_wordmark.webp'), findsOneWidget);
  });

  testWidgets('el selector de período no lleva calendario y ocupa todo el ancho', (tester) async {
    await pumpDashboard(tester);

    expect(find.byIcon(Icons.calendar_month_outlined), findsNothing);
    // La pantalla mide 360 y la lista tiene 14 de margen a cada lado.
    expect(tester.getTopLeft(find.text('7 días')).dx, lessThan(60));
    expect(tester.getTopRight(find.text('12 meses')).dx, greaterThan(300));
  });

  testWidgets('el texto de la tarjeta de bienvenida está centrado y no pegado abajo', (tester) async {
    await pumpDashboard(tester);

    final title = find.text('Sistema Inteligente\nde Mantenimiento');
    final hero = tester.getRect(find.ancestor(of: title, matching: find.byType(ClipRRect)).first);
    final center = tester.getCenter(title);

    expect((center.dx - hero.center.dx).abs(), lessThan(6), reason: 'centrado horizontalmente');
    expect(center.dy, inInclusiveRange(hero.top + hero.height * 0.3, hero.top + hero.height * 0.6), reason: 'un poco por encima del centro, no al fondo');
  });

  testWidgets('los indicadores muestran valor, variación y nota con los datos reales', (tester) async {
    await pumpDashboard(tester);

    expect(find.text('2,6 d'), findsOneWidget);
    expect(find.text('Resolución · 1.ª asignación en 36,8 h'), findsOneWidget);
    expect(find.text('54,8%'), findsOneWidget);
    expect(find.text('23 de 42 a tiempo'), findsOneWidget);
    expect(find.text('81,6%'), findsOneWidget);
    expect(find.text('31 de 38 equipos operativos'), findsOneWidget);
    expect(find.text('▲ 20,9%'), findsOneWidget);
    expect(find.text('▼ 6,0%'), findsOneWidget);
    expect(find.text('▲ 1,2%'), findsOneWidget);
    expect(find.text('▲ 25,0%'), findsOneWidget);
    expect(find.text('vs. período anterior · n=42'), findsNWidgets(2));
    expect(find.text('vs. inicio del período'), findsNWidgets(2));
  });

  testWidgets('el selector de período vuelve a pedir los datos', (tester) async {
    await pumpDashboard(tester);
    expect(find.text('7 días'), findsOneWidget);
    expect(find.text('30 días'), findsOneWidget);
    expect(find.text('12 meses'), findsOneWidget);

    await tester.tap(find.text('7 días'));
    await tester.pumpAndSettle();

    verify(() => repository.loadKpis('7d')).called(1);
  });

  testWidgets('la tabla de técnicos muestra las columnas y las notas de pocos datos', (tester) async {
    await pumpDashboard(tester);

    for (final header in ['TÉCNICO', 'ABIERTOS', 'RESUELTOS', 'SLA', 'N', 'REAB.']) {
      expect(find.text(header), findsOneWidget);
    }
    expect(find.text('Luis Demo'), findsOneWidget);
    expect(find.text('Hardware'), findsOneWidget);
    expect(find.text('2,8 d'), findsOneWidget);
    expect(find.text('55,6%'), findsOneWidget);
    expect(find.text('(n=18)'), findsOneWidget);
    expect(find.text('pocos datos'), findsOneWidget);
    expect(find.text('Ver técnicos →'), findsOneWidget);
  });

  testWidgets('el ranking de equipos numera los equipos y la atención inmediata marca el SLA vencido', (tester) async {
    await pumpDashboard(tester);

    expect(find.text('DEMO-001  Dell Latitude 5420'), findsOneWidget);
    expect(find.text('Ver todos →'), findsOneWidget);
    expect(find.text('DEMO-T-0042 · No puede iniciar sesión'), findsOneWidget);
    expect(find.textContaining('sin asignar'), findsOneWidget);
    expect(find.textContaining('vence 8 oct 2026'), findsOneWidget);
    expect(find.text('SLA vencido'), findsOneWidget);
  });

  testWidgets('sin permiso de ver técnicos o equipos no aparecen esos enlaces', (tester) async {
    await pumpDashboard(tester, user: profile(permissions: const ['dashboard:ver_todos', 'tickets:ver_todos']));

    expect(find.text('Ver técnicos →'), findsNothing);
    expect(find.text('Ver todos →'), findsNothing);
  });

  testWidgets('con la fuente del sistema más grande no se desborda', (tester) async {
    await pumpDashboard(tester, textScale: 1.3);

    expect(tester.takeException(), isNull);
    expect(find.text('Luis Demo'), findsOneWidget);
  });
}
