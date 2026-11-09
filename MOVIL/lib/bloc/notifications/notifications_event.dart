part of 'notifications_bloc.dart';

sealed class NotificationsEvent {
  const NotificationsEvent();
}

/// Carga (o recarga, o reintenta) la bandeja.
class NotificationsLoaded extends NotificationsEvent {
  const NotificationsLoaded({this.done});

  /// Se completa al terminar.
  final Completer<void>? done;
}

/// Vacía la bandeja (al cerrar sesión).
class NotificationsCleared extends NotificationsEvent {
  const NotificationsCleared();
}

/// Marca una notificación como leída.
class NotificationRead extends NotificationsEvent {
  const NotificationRead(this.id);

  final int id;
}

/// Marca todas como leídas.
class AllNotificationsRead extends NotificationsEvent {
  const AllNotificationsRead();
}
