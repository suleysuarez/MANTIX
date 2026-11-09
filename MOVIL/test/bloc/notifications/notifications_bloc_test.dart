import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/notifications/notifications_bloc.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/models/notifications/notification_models.dart';
import 'package:mantix/repositories/notifications/notifications_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockNotificationsRepository extends Mock implements NotificationsRepository {}

AppNotification _item(int id, {bool read = false}) => AppNotification(
      id: id,
      title: 'Aviso $id',
      message: 'Mensaje $id',
      type: 'info',
      isRead: read,
      createdAt: DateTime.utc(2026, 11, 2),
    );

void main() {
  late _MockNotificationsRepository repository;
  final inbox = NotificationInbox(unreadCount: 2, items: [_item(1), _item(2), _item(3, read: true)]);

  setUp(() {
    repository = _MockNotificationsRepository();
    when(() => repository.inbox()).thenAnswer((_) async => inbox);
    when(() => repository.markRead(any())).thenAnswer((_) async {});
    when(() => repository.markAllRead()).thenAnswer((_) async {});
  });

  Future<NotificationsBloc> loaded() async {
    final bloc = NotificationsBloc(repository: repository)..add(const NotificationsLoaded());
    addTearDown(bloc.close);
    await bloc.stream.firstWhere((s) => s.status == NotificationsStatus.success);
    return bloc;
  }

  test('carga la bandeja y expone las no leídas', () async {
    final bloc = await loaded();

    expect(bloc.state.inbox, inbox);
    expect(bloc.state.unreadCount, 2);
  });

  test('un error sin datos previos deja el estado de fallo', () async {
    when(() => repository.inbox()).thenThrow(const NetworkFailure());
    final bloc = NotificationsBloc(repository: repository)..add(const NotificationsLoaded());
    addTearDown(bloc.close);

    await bloc.stream.firstWhere((s) => s.status == NotificationsStatus.failure);

    expect(bloc.state.inbox, isNull);
    expect(bloc.state.failure, isA<NetworkFailure>());
  });

  test('si un refresco falla se conserva la última bandeja', () async {
    final bloc = await loaded();
    when(() => repository.inbox()).thenThrow(const NetworkFailure());

    await bloc.reload();

    expect(bloc.state.status, NotificationsStatus.failure);
    expect(bloc.state.inbox, inbox);
  });

  test('marcar una como leída actualiza al instante y avisa al servidor', () async {
    final bloc = await loaded();

    bloc.add(const NotificationRead(1));
    await bloc.stream.firstWhere((s) => s.unreadCount == 1);

    expect(bloc.state.inbox!.items.first.isRead, isTrue);
    expect(bloc.state.inbox!.items[1].isRead, isFalse);
    verify(() => repository.markRead(1)).called(1);
  });

  test('una ya leída no vuelve a avisar al servidor', () async {
    final bloc = await loaded();

    bloc.add(const NotificationRead(3));
    await Future<void>.delayed(Duration.zero);

    verifyNever(() => repository.markRead(any()));
    expect(bloc.state.unreadCount, 2);
  });

  test('si el servidor falla al marcar, se vuelve a pedir la bandeja', () async {
    final bloc = await loaded();
    when(() => repository.markRead(any())).thenThrow(const NetworkFailure());

    bloc.add(const NotificationRead(1));
    await bloc.stream.firstWhere((s) => s.unreadCount == 1);
    await bloc.stream.firstWhere((s) => s.unreadCount == 2);

    verify(() => repository.inbox()).called(2);
  });

  test('marcar todas deja el contador en cero', () async {
    final bloc = await loaded();

    bloc.add(const AllNotificationsRead());
    await bloc.stream.firstWhere((s) => s.unreadCount == 0);

    expect(bloc.state.inbox!.items.every((i) => i.isRead), isTrue);
    verify(() => repository.markAllRead()).called(1);
  });

  test('marcar todas sin pendientes no llama al servidor', () async {
    when(() => repository.inbox()).thenAnswer((_) async => NotificationInbox(items: [_item(1, read: true)]));
    final bloc = await loaded();

    bloc.add(const AllNotificationsRead());
    await Future<void>.delayed(Duration.zero);

    verifyNever(() => repository.markAllRead());
  });

  test('al cerrar sesión se vacía la bandeja', () async {
    final bloc = await loaded();

    bloc.add(const NotificationsCleared());
    await bloc.stream.firstWhere((s) => s.inbox == null);

    expect(bloc.state.unreadCount, 0);
  });
}
