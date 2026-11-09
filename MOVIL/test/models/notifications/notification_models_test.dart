import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/models/notifications/notification_models.dart';

Map<String, Object?> notificationJson({int id = 1, bool isRead = false, String title = 'Ticket asignado'}) => {
      'id': id,
      'title': title,
      'message': 'Se te asignó el ticket TCK-0001.',
      'notification_type': 'ticket_assigned',
      'is_read': isRead,
      'read_at': isRead ? '2026-11-02T16:00:00Z' : null,
      'link_url': '/tickets/1',
      'created_at': '2026-11-02T15:30:00Z',
    };

void main() {
  test('lee una notificación', () {
    final item = AppNotification.fromJson(notificationJson());

    expect(item.id, 1);
    expect(item.title, 'Ticket asignado');
    expect(item.message, 'Se te asignó el ticket TCK-0001.');
    expect(item.type, 'ticket_assigned');
    expect(item.isRead, isFalse);
    expect(item.createdAt, DateTime.utc(2026, 11, 2, 15, 30));
  });

  test('asRead conserva todo salvo el estado de lectura', () {
    final item = AppNotification.fromJson(notificationJson());
    final read = item.asRead();

    expect(read.isRead, isTrue);
    expect(read.id, item.id);
    expect(read.title, item.title);
    expect(read.createdAt, item.createdAt);
  });

  test('lee la bandeja con su contador de no leídas', () {
    final inbox = NotificationInbox.fromJson({
      'unread_count': 2,
      'items': [notificationJson(), notificationJson(id: 2, isRead: true)],
    });

    expect(inbox.unreadCount, 2);
    expect(inbox.items.map((i) => i.id), [1, 2]);
  });

  test('una bandeja sin elementos ni contador queda vacía', () {
    final inbox = NotificationInbox.fromJson(const {});

    expect(inbox.unreadCount, 0);
    expect(inbox.items, isEmpty);
  });
}
