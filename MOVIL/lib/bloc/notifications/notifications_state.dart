part of 'notifications_bloc.dart';

enum NotificationsStatus { loading, success, failure }

class NotificationsState extends Equatable {
  const NotificationsState({this.status = NotificationsStatus.loading, this.inbox, this.failure});

  final NotificationsStatus status;

  /// Última bandeja cargada; se conserva si un refresco falla.
  final NotificationInbox? inbox;
  final Failure? failure;

  int get unreadCount => inbox?.unreadCount ?? 0;

  @override
  List<Object?> get props => [status, inbox, failure];
}
