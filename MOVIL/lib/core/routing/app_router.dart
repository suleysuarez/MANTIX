import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/no_access_screen.dart';
import '../../features/auth/presentation/pending_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/auth/presentation/unavailable_screen.dart';
import '../../features/dev/presentation/components_gallery_screen.dart';
import '../../features/home/presentation/home_placeholder_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/requests/presentation/create_request_screen.dart';
import '../../features/requests/presentation/my_requests_screen.dart';
import '../../features/requests/presentation/request_detail_screen.dart';
import '../auth/home_resolver.dart';
import '../auth/session.dart';
import '../auth/user_profile.dart';

abstract final class AppRoutes {
  static const splash = '/';
  static const login = '/ingresar';
  static const pending = '/pendiente';
  static const noAccess = '/sin-acceso';
  static const unavailable = '/sin-conexion';
}

/// Decide a dónde va el usuario según la sesión. Función pura para poder probarla.
///
/// Devuelve `null` si la ruta actual ya es correcta.
String? redirectFor({required AsyncValue<SessionState> session, required String location}) {
  final value = session.value;
  if (value == null) {
    return location == AppRoutes.splash ? null : AppRoutes.splash;
  }
  final String target = switch (value) {
    SignedOut() => AppRoutes.login,
    SessionUnavailable() => AppRoutes.unavailable,
    SignedIn(:final profile) => switch (profile.status) {
        AccountStatus.pendingApproval => AppRoutes.pending,
        AccountStatus.noAccess => AppRoutes.noAccess,
        AccountStatus.active => _activeTarget(profile, location),
      },
  };
  return target == location ? null : target;
}

/// Con sesión activa se permanece en cualquier pantalla de la app; solo se sale
/// de las de acceso (splash, login, pendiente, sin acceso y sin conexión).
String _activeTarget(UserProfile profile, String location) {
  const gate = {
    AppRoutes.splash,
    AppRoutes.login,
    AppRoutes.pending,
    AppRoutes.noAccess,
    AppRoutes.unavailable,
  };
  if (gate.contains(location)) return resolveHome(profile.permissions).path;
  // Rutas que exigen un permiso: sin él se vuelve al inicio. Solo oculta la
  // pantalla; la autorización real es del backend.
  final required = _routePermissions[location];
  if (required != null && !profile.permissions.contains(required)) return resolveHome(profile.permissions).path;
  return location;
}

const _routePermissions = {RequestRoutes.create: 'solicitudes:crear'};

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen<AsyncValue<SessionState>>(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => redirectFor(
      session: ref.read(sessionProvider),
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: AppRoutes.pending, builder: (_, _) => const PendingScreen()),
      GoRoute(path: AppRoutes.noAccess, builder: (_, _) => const NoAccessScreen()),
      GoRoute(path: AppRoutes.unavailable, builder: (_, _) => const UnavailableScreen()),
      GoRoute(path: HomeDestination.profile.path, builder: (_, _) => const ProfileScreen()),
      // Solo en debug: no existe en las compilaciones de producción.
      if (kDebugMode) GoRoute(path: ComponentsGalleryScreen.path, builder: (_, _) => const ComponentsGalleryScreen()),
      GoRoute(path: HomeDestination.myRequests.path, builder: (_, _) => const MyRequestsScreen()),
      GoRoute(path: RequestRoutes.create, builder: (_, _) => const CreateRequestScreen()),
      GoRoute(
        path: '/solicitudes/:id',
        builder: (_, state) => RequestDetailScreen(requestId: int.parse(state.pathParameters['id']!)),
        // Un id que no es número no abre el detalle: vuelve al inicio.
        redirect: (_, state) => int.tryParse(state.pathParameters['id'] ?? '') == null ? HomeDestination.myRequests.path : null,
      ),
      for (final destination in HomeDestination.values.where((d) => d != HomeDestination.profile && d != HomeDestination.myRequests))
        GoRoute(path: destination.path, builder: (_, _) => HomePlaceholderScreen(destination: destination)),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
