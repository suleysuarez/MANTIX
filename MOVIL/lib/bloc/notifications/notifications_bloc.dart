import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/notifications/notification_models.dart';
import '../../repositories/notifications/notifications_repository.dart';

part 'notifications_event.dart';
part 'notifications_state.dart';

/// Notificaciones del usuario: alimentan la campana de todos los módulos y su panel.
/// Se cargan al iniciar sesión (`NotificationsLoaded`) y se vacían al cerrarla.
class NotificationsBloc extends Bloc<NotificationsEvent, NotificationsState> {
  NotificationsBloc({required this._repository}) : super(const NotificationsState()) {
    on<NotificationsLoaded>(_onLoaded);
    on<NotificationsCleared>((_, emit) => emit(const NotificationsState()));
    on<NotificationRead>(_onRead);
    on<AllNotificationsRead>(_onAllRead);
  }

  final NotificationsRepository _repository;

  /// Vuelve a pedir la bandeja y espera a que termine (al abrir el panel).
  Future<void> reload() {
    final done = Completer<void>();
    add(NotificationsLoaded(done: done));
    return done.future;
  }

  Future<void> _onLoaded(NotificationsLoaded event, Emitter<NotificationsState> emit) async {
    // Con datos ya cargados se siguen mostrando mientras llegan los nuevos.
    if (state.inbox == null && state.status != NotificationsStatus.loading) emit(const NotificationsState());
    try {
      emit(NotificationsState(status: NotificationsStatus.success, inbox: await _repository.inbox()));
    } catch (error) {
      emit(NotificationsState(status: NotificationsStatus.failure, inbox: state.inbox, failure: toFailure(error)));
    } finally {
      event.done?.complete();
    }
  }

  Future<void> _onRead(NotificationRead event, Emitter<NotificationsState> emit) async {
    final inbox = state.inbox;
    if (inbox == null) return;
    final target = inbox.items.where((item) => item.id == event.id && !item.isRead);
    if (target.isEmpty) return;
    // Se marca al instante en pantalla; si el servidor falla se vuelve a pedir la bandeja.
    emit(NotificationsState(
      status: NotificationsStatus.success,
      inbox: NotificationInbox(
        unreadCount: inbox.unreadCount > 0 ? inbox.unreadCount - 1 : 0,
        items: [for (final item in inbox.items) item.id == event.id ? item.asRead() : item],
      ),
    ));
    try {
      await _repository.markRead(event.id);
    } catch (_) {
      add(const NotificationsLoaded());
    }
  }

  Future<void> _onAllRead(AllNotificationsRead event, Emitter<NotificationsState> emit) async {
    final inbox = state.inbox;
    if (inbox == null || inbox.unreadCount == 0) return;
    emit(NotificationsState(
      status: NotificationsStatus.success,
      inbox: NotificationInbox(unreadCount: 0, items: [for (final item in inbox.items) item.asRead()]),
    ));
    try {
      await _repository.markAllRead();
    } catch (_) {
      add(const NotificationsLoaded());
    }
  }
}
