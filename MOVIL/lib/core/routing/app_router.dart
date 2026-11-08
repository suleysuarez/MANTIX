import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/no_access_screen.dart';
import '../../features/auth/presentation/pending_screen.dart';
import '../../features/auth/presentation/unavailable_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/dev/presentation/components_gallery_screen.dart';
import '../../features/home/presentation/home_placeholder_screen.dart';
import '../../features/home/presentation/dashboard_screen.dart';
import '../../features/home/presentation/module_placeholder_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/requests/presentation/create_request_screen.dart';
import '../../features/requests/presentation/my_requests_screen.dart';
import '../../features/requests/presentation/request_detail_screen.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../auth/home_resolver.dart';
import '../../models/auth/user_profile.dart';

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
String? redirectFor({required AuthState auth, required String location}) {
  final String target = switch (auth) {
    AuthUnknown() => AppRoutes.splash,
    AuthUnauthenticated() => AppRoutes.login,
    AuthUnavailable() => AppRoutes.unavailable,
    AuthPending() => AppRoutes.pending,
    AuthNoAccess() => AppRoutes.noAccess,
    Authenticated(:final profile) => _activeTarget(profile, location),
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

/// Hace que `go_router` reevalúe `redirect` cada vez que el [Stream] emite.
/// Así el router solo reacciona al estado de sesión; no contiene lógica de negocio.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<Object?> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

/// Crea el router de la app a partir del estado del AuthBloc.
GoRouter createAppRouter({required AuthBloc authBloc, required Listenable refresh}) {
  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => redirectFor(auth: authBloc.state, location: state.matchedLocation),
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: AppRoutes.pending, builder: (_, _) => const PendingScreen()),
      GoRoute(path: AppRoutes.unavailable, builder: (_, _) => const UnavailableScreen()),
      GoRoute(path: AppRoutes.noAccess, builder: (_, _) => const NoAccessScreen()),
      GoRoute(path: HomeDestination.profile.path, builder: (_, _) => const ProfileScreen()),
      GoRoute(path: HomeDestination.globalDashboard.path, builder: (_, _) => const DashboardScreen(destination: HomeDestination.globalDashboard)),
      GoRoute(path: HomeDestination.ownDashboard.path, builder: (_, _) => const DashboardScreen(destination: HomeDestination.ownDashboard)),
      GoRoute(path: '/modulos/:module', builder: (_, state) => ModulePlaceholderScreen(module: state.pathParameters['module'] ?? '')),
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
      for (final destination in HomeDestination.values.where((d) => d != HomeDestination.profile && d != HomeDestination.myRequests && d != HomeDestination.globalDashboard && d != HomeDestination.ownDashboard))
        GoRoute(path: destination.path, builder: (_, _) => HomePlaceholderScreen(destination: destination)),
    ],
  );
  return router;
}
