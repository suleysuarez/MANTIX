import 'package:bloc_test/bloc_test.dart';
import 'package:mantix/bloc/auth/auth_bloc.dart';
import 'package:mantix/bloc/notifications/notifications_bloc.dart';
import 'package:mantix/models/auth/user_profile.dart';
import 'package:mantix/models/notifications/notification_models.dart';

/// Lo que necesita el encabezado de los módulos (`MantixAppBar`): la sesión y las notificaciones.
class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class MockNotificationsBloc extends MockBloc<NotificationsEvent, NotificationsState> implements NotificationsBloc {}

UserProfile testProfile({Set<String> permissions = const {}}) => UserProfile(
      id: 1,
      email: 'ana@mantix.test',
      fullName: 'Ana Pérez',
      isActive: true,
      roles: const ['ADMIN'],
      permissions: permissions,
    );

MockAuthBloc authenticatedBloc(UserProfile profile) {
  final bloc = MockAuthBloc();
  whenListen(bloc, const Stream<AuthState>.empty(), initialState: Authenticated(profile));
  return bloc;
}

/// Bandeja ya cargada (por defecto, vacía y sin notificaciones por leer).
MockNotificationsBloc notificationsBloc({NotificationInbox inbox = const NotificationInbox(), NotificationsState? state}) {
  final bloc = MockNotificationsBloc();
  whenListen(
    bloc,
    const Stream<NotificationsState>.empty(),
    initialState: state ?? NotificationsState(status: NotificationsStatus.success, inbox: inbox),
  );
  return bloc;
}
