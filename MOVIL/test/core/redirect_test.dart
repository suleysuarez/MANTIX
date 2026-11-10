import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/auth/auth_bloc.dart';
import 'package:mantix/core/routing/home_resolver.dart';
import 'package:mantix/models/auth/user_profile.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/core/routing/app_router.dart';
import 'package:mantix/pages/queue/pending_requests_screen.dart';
import 'package:mantix/pages/users/users_screen.dart';

UserProfile profile({List<String> roles = const ['ROL'], Set<String> permissions = const {}}) => UserProfile(
      id: 1,
      email: 'a@b.c',
      fullName: 'Ana',
      isActive: true,
      roles: roles,
      permissions: permissions,
    );

/// Estado de sesión que resultaría de cargar [p] (igual que lo decide el `AuthBloc`).
AuthState signedIn(UserProfile p) => switch (p.status) {
      AccountStatus.pendingApproval => AuthPending(p),
      AccountStatus.noAccess => AuthNoAccess(p),
      AccountStatus.active => Authenticated(p),
    };

String? redirect(AuthState state, String location) => redirectFor(auth: state, location: location);

void main() {
  test('mientras carga la sesión, todo va a la pantalla de carga', () {
    expect(redirect(const AuthUnknown(), AppRoutes.login), AppRoutes.splash);
    expect(redirect(const AuthUnknown(), AppRoutes.splash), isNull);
  });

  test('sin sesión va al login', () {
    expect(redirect(const AuthUnauthenticated(), AppRoutes.splash), AppRoutes.login);
    expect(redirect(const AuthUnauthenticated(), HomeDestination.profile.path), AppRoutes.login);
    expect(redirect(const AuthUnauthenticated(), AppRoutes.login), isNull);
  });

  test('error al cargar el perfil va a sin conexión', () {
    expect(redirect(const AuthUnavailable(NetworkFailure()), AppRoutes.splash), AppRoutes.unavailable);
  });

  test('cuenta sin roles va a pendiente y con roles sin permisos a sin acceso', () {
    expect(redirect(signedIn(profile(roles: const [])), AppRoutes.splash), AppRoutes.pending);
    expect(redirect(signedIn(profile()), AppRoutes.splash), AppRoutes.noAccess);
    expect(redirect(signedIn(profile()), AppRoutes.noAccess), isNull);
  });

  test('cuenta activa sale de las pantallas de acceso hacia su inicio', () {
    final state = signedIn(profile(permissions: const {'tickets:ver_asignados'}));
    expect(redirect(state, AppRoutes.splash), HomeDestination.assignedInbox.path);
    expect(redirect(state, AppRoutes.login), HomeDestination.assignedInbox.path);
    expect(redirect(state, AppRoutes.pending), HomeDestination.assignedInbox.path);
  });

  test('cuenta activa no es expulsada de las pantallas de la app', () {
    final state = signedIn(profile(permissions: const {'tickets:ver_asignados'}));
    expect(redirect(state, HomeDestination.profile.path), isNull);
    expect(redirect(state, HomeDestination.assignedInbox.path), isNull);
  });

  test('cuenta activa sin criterio de inicio cae en Perfil', () {
    expect(redirect(signedIn(profile(permissions: const {'tickets:ver'})), AppRoutes.splash), HomeDestination.profile.path);
  });

  test('la gestión de equipos exige el permiso equipos:ver', () {
    final withPermission = signedIn(profile(permissions: const {'equipos:ver', 'tickets:ver_asignados'}));
    final withoutPermission = signedIn(profile(permissions: const {'tickets:ver_asignados'}));
    expect(redirect(withPermission, '/modulos/equipos'), isNull);
    expect(redirect(withoutPermission, '/modulos/equipos'), HomeDestination.assignedInbox.path);
    // Los demás módulos siguen sin exigir un permiso propio en el router.
    expect(redirect(withoutPermission, '/modulos/tickets'), isNull);
  });

  test('la bandeja de solicitudes pendientes exige solicitudes:ver_todos y, sin él, vuelve al inicio', () {
    const path = PendingRequestsScreen.path;
    final withPermission = signedIn(profile(permissions: const {'solicitudes:ver_todos', 'tickets:ver_asignados'}));
    expect(redirect(withPermission, path), isNull);

    // Poder ver las propias solicitudes no basta.
    final only = signedIn(profile(permissions: const {'solicitudes:ver', 'tickets:ver_asignados'}));
    expect(redirect(only, path), HomeDestination.assignedInbox.path);
  });

  test('Usuarios y roles exige usuarios:ver y, sin él, vuelve al inicio', () {
    const path = UsersScreen.path;
    expect(redirect(signedIn(profile(permissions: const {'usuarios:ver', 'tickets:ver_asignados'})), path), isNull);
    expect(redirect(signedIn(profile(permissions: const {'usuarios:asignar', 'tickets:ver_asignados'})), path), HomeDestination.assignedInbox.path, reason: 'asignar sin poder ver tampoco basta');
  });
}
