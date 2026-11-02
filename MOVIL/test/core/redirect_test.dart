import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/auth/home_resolver.dart';
import 'package:mantix/core/auth/session.dart';
import 'package:mantix/core/auth/user_profile.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/core/routing/app_router.dart';

UserProfile profile({List<String> roles = const ['ROL'], Set<String> permissions = const {}}) => UserProfile(
      id: 1,
      email: 'a@b.c',
      fullName: 'Ana',
      isActive: true,
      roles: roles,
      permissions: permissions,
    );

String? redirect(SessionState? state, String location) =>
    redirectFor(session: state == null ? const AsyncLoading() : AsyncData(state), location: location);

void main() {
  test('mientras carga la sesión, todo va a la pantalla de carga', () {
    expect(redirect(null, AppRoutes.login), AppRoutes.splash);
    expect(redirect(null, AppRoutes.splash), isNull);
  });

  test('sin sesión va al login', () {
    expect(redirect(const SignedOut(), AppRoutes.splash), AppRoutes.login);
    expect(redirect(const SignedOut(), HomeDestination.profile.path), AppRoutes.login);
    expect(redirect(const SignedOut(), AppRoutes.login), isNull);
  });

  test('error al cargar el perfil va a sin conexión', () {
    expect(redirect(const SessionUnavailable(NetworkFailure()), AppRoutes.splash), AppRoutes.unavailable);
  });

  test('cuenta sin roles va a pendiente y con roles sin permisos a sin acceso', () {
    expect(redirect(SignedIn(profile(roles: const [])), AppRoutes.splash), AppRoutes.pending);
    expect(redirect(SignedIn(profile()), AppRoutes.splash), AppRoutes.noAccess);
    expect(redirect(SignedIn(profile()), AppRoutes.noAccess), isNull);
  });

  test('cuenta activa sale de las pantallas de acceso hacia su inicio', () {
    final signedIn = SignedIn(profile(permissions: const {'tickets:ver_asignados'}));
    expect(redirect(signedIn, AppRoutes.splash), HomeDestination.assignedInbox.path);
    expect(redirect(signedIn, AppRoutes.login), HomeDestination.assignedInbox.path);
    expect(redirect(signedIn, AppRoutes.pending), HomeDestination.assignedInbox.path);
  });

  test('cuenta activa no es expulsada de las pantallas de la app', () {
    final signedIn = SignedIn(profile(permissions: const {'tickets:ver_asignados'}));
    expect(redirect(signedIn, HomeDestination.profile.path), isNull);
    expect(redirect(signedIn, HomeDestination.assignedInbox.path), isNull);
  });

  test('cuenta activa sin criterio de inicio cae en Perfil', () {
    expect(redirect(SignedIn(profile(permissions: const {'tickets:ver'})), AppRoutes.splash), HomeDestination.profile.path);
  });
}
