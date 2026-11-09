import 'package:equatable/equatable.dart';

/// Una notificación de la bandeja del usuario.
class AppNotification extends Equatable {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, Object?> json) => AppNotification(
        id: json['id']! as int,
        title: json['title']! as String,
        message: json['message']! as String,
        type: (json['notification_type'] as String?) ?? '',
        isRead: json['is_read'] == true,
        createdAt: DateTime.parse(json['created_at']! as String),
      );

  final int id;
  final String title;
  final String message;
  final String type;
  final bool isRead;
  final DateTime createdAt;

  AppNotification asRead() => AppNotification(id: id, title: title, message: message, type: type, isRead: true, createdAt: createdAt);

  @override
  List<Object?> get props => [id, title, message, type, isRead, createdAt];
}

/// Bandeja de notificaciones (`GET /notifications`): las más recientes y cuántas faltan por leer.
class NotificationInbox extends Equatable {
  const NotificationInbox({this.unreadCount = 0, this.items = const []});

  factory NotificationInbox.fromJson(Map<String, Object?> json) {
    final items = json['items'];
    return NotificationInbox(
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      items: [if (items is List) for (final item in items) AppNotification.fromJson((item as Map).cast<String, Object?>())],
    );
  }

  final int unreadCount;
  final List<AppNotification> items;

  @override
  List<Object?> get props => [unreadCount, items];
}
