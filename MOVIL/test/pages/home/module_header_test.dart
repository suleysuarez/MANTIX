import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/auth/auth_bloc.dart';
import 'package:mantix/bloc/notifications/notifications_bloc.dart';
import 'package:mantix/core/routing/home_resolver.dart';
import 'package:mantix/core/theme/app_theme.dart';
import 'package:mantix/pages/home/home_placeholder_screen.dart';
import 'package:mantix/pages/home/module_placeholder_screen.dart';

import '../../support/header_support.dart';

/// El encabezado de todos los módulos: la «M», la campana de notificaciones, el avatar y el menú.
void main() {
  Future<void> pumpScreen(WidgetTester tester, Widget screen, {Set<String> permissions = const {'tickets:ver', 'equipos:ver', 'tickets:ver_asignados'}}) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: authenticatedBloc(testProfile(permissions: permissions))),
          BlocProvider<NotificationsBloc>.value(value: notificationsBloc()),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool isMark(Widget widget) => widget is Image && (widget.image as AssetImage).assetName == 'assets/images/mantix_m.webp';

  void expectHeader() {
    expect(find.byWidgetPredicate(isMark), findsOneWidget);
    expect(find.byTooltip('Notificaciones'), findsOneWidget);
    expect(find.byTooltip('Perfil'), findsOneWidget);
    expect(find.byTooltip('Open navigation menu'), findsOneWidget);
  }

  testWidgets('un módulo todavía sin construir trae el encabezado y el menú', (tester) async {
    await pumpScreen(tester, const ModulePlaceholderScreen(module: 'tickets'));

    expectHeader();
    expect(find.text('Tickets'), findsOneWidget);
    expect(find.text('Ir al inicio'), findsOneWidget);

    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
    expect(find.text('Equipos'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);
  });

  testWidgets('la bandeja y los reportes también traen el encabezado', (tester) async {
    await pumpScreen(tester, const HomePlaceholderScreen(destination: HomeDestination.assignedInbox));

    expectHeader();
    expect(find.text('Mi bandeja de trabajo'), findsOneWidget);
  });
}
