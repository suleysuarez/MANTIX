import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/repositories/notifications/notifications_repository.dart';

import '../../models/notifications/notification_models_test.dart' show notificationJson;
import '../../support/fakes.dart';
import '../../support/requests_support.dart';

void main() {
  test('inbox lee la bandeja y el contador', () async {
    final adapter = FakeAdapter((_) => jsonResponse(200, {'unread_count': 1, 'items': [notificationJson()]}));
    final inbox = await NotificationsRepository(dioWith(adapter)).inbox();

    expect(adapter.requests.single.path, '/notifications');
    expect(inbox.unreadCount, 1);
    expect(inbox.items.single.title, 'Ticket asignado');
  });

  test('markRead hace POST a la notificación', () async {
    final adapter = FakeAdapter((_) => jsonResponse(200, {}));
    await NotificationsRepository(dioWith(adapter)).markRead(7);

    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path, '/notifications/7/read');
  });

  test('markAllRead hace POST a read-all', () async {
    final adapter = FakeAdapter((_) => jsonResponse(200, {}));
    await NotificationsRepository(dioWith(adapter)).markAllRead();

    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path, '/notifications/read-all');
  });

  test('un error del servidor sale como Failure sin detalles internos', () async {
    final adapter = FakeAdapter((_) => errorResponse(500));

    await expectLater(NotificationsRepository(dioWith(adapter)).inbox(), throwsA(isA<ServerFailure>()));
  });
}
