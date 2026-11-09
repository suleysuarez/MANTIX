import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/notifications/notifications_bloc.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/core/theme/app_theme.dart';
import 'package:mantix/models/notifications/notification_models.dart';
import 'package:mantix/widgets/home/mantix_app_bar.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/header_support.dart';

AppNotification _item(int id, {bool read = false}) => AppNotification(
      id: id,
      title: 'Aviso $id',
      message: 'Mensaje del aviso $id',
      type: 'info',
      isRead: read,
      createdAt: DateTime.utc(2026, 10, 8, 15, 30),
    );

void main() {
  setUpAll(() => registerFallbackValue(const NotificationsLoaded()));

  Future<void> pumpBar(WidgetTester tester, MockNotificationsBloc bloc) async {
    await tester.pumpWidget(
      BlocProvider<NotificationsBloc>.value(
        value: bloc,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(appBar: MantixAppBar(profile: testProfile()), body: const SizedBox()),
        ),
      ),
    );
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pumpAndSettle();
  }

  Finder dot() => find.byWidgetPredicate((w) => w is Container && w.constraints?.maxWidth == 9);

  testWidgets('la campana avisa cuántas notificaciones hay sin leer', (tester) async {
    await pumpBar(tester, notificationsBloc(inbox: NotificationInbox(unreadCount: 3, items: [_item(1)])));

    expect(find.byTooltip('Notificaciones, 3 sin leer'), findsOneWidget);
    expect(dot(), findsOneWidget);
  });

  testWidgets('sin notificaciones por leer no hay punto', (tester) async {
    await pumpBar(tester, notificationsBloc(inbox: NotificationInbox(items: [_item(1, read: true)])));

    expect(find.byTooltip('Notificaciones'), findsOneWidget);
    expect(dot(), findsNothing);
  });

  testWidgets('tocar la campana abre el panel y vuelve a pedir la bandeja', (tester) async {
    final bloc = notificationsBloc(inbox: NotificationInbox(unreadCount: 1, items: [_item(1), _item(2, read: true)]));
    await pumpBar(tester, bloc);

    await openSheet(tester);

    verify(() => bloc.add(any(that: isA<NotificationsLoaded>()))).called(1);
    expect(find.text('Notificaciones'), findsOneWidget);
    expect(find.text('Aviso 1'), findsOneWidget);
    expect(find.text('Mensaje del aviso 2'), findsOneWidget);
    expect(find.text('1 sin leer'), findsOneWidget);
    expect(find.text('Marcar todas como leídas'), findsOneWidget);
    expect(find.textContaining('8 oct 2026'), findsNWidgets(2));
  });

  testWidgets('tocar una notificación sin leer la marca como leída', (tester) async {
    final bloc = notificationsBloc(inbox: NotificationInbox(unreadCount: 1, items: [_item(5)]));
    await pumpBar(tester, bloc);
    await openSheet(tester);

    await tester.tap(find.text('Aviso 5'));

    final event = verify(() => bloc.add(captureAny(that: isA<NotificationRead>()))).captured.single as NotificationRead;
    expect(event.id, 5);
  });

  testWidgets('«Marcar todas como leídas» lo pide al Bloc', (tester) async {
    final bloc = notificationsBloc(inbox: NotificationInbox(unreadCount: 2, items: [_item(1), _item(2)]));
    await pumpBar(tester, bloc);
    await openSheet(tester);

    await tester.tap(find.text('Marcar todas como leídas'));

    verify(() => bloc.add(any(that: isA<AllNotificationsRead>()))).called(1);
  });

  testWidgets('sin notificaciones lo dice y no ofrece marcar todas', (tester) async {
    await pumpBar(tester, notificationsBloc());
    await openSheet(tester);

    expect(find.text('No tienes notificaciones.'), findsOneWidget);
    expect(find.text('Marcar todas como leídas'), findsNothing);
  });

  testWidgets('si no se pudo cargar muestra el error con reintento', (tester) async {
    final bloc = notificationsBloc(state: const NotificationsState(status: NotificationsStatus.failure, failure: NetworkFailure()));
    await pumpBar(tester, bloc);
    await openSheet(tester);

    expect(find.text('Reintentar'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));

    verify(() => bloc.add(any(that: isA<NotificationsLoaded>()))).called(2);
  });

  testWidgets('mientras carga muestra el indicador', (tester) async {
    await pumpBar(tester, notificationsBloc(state: const NotificationsState()));
    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.bySemanticsLabel('Cargando notificaciones'), findsOneWidget);
  });
}
