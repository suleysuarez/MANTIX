import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../errors/failure.dart';
import '../auth_provider.dart';
import '../auth_repository.dart';
import '../user_profile.dart';

part 'auth_event.dart';
part 'auth_state.dart';

/// Sesión de la app. Envuelve al [AuthProvider] (Clerk) sin duplicar su estado:
/// Clerk sigue siendo la fuente de verdad de «hay sesión» y este Bloc solo
/// resuelve qué significa para la app (perfil, roles y permisos de `/auth/me`).
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required this._auth, required this._repository}) : super(const AuthUnknown()) {
    on<AuthStarted>((_, emit) async => emit(await _loadOnce()));
    on<AuthRefreshRequested>(_onRefresh);
    on<AuthSignOutRequested>(_onSignOut);
    on<AuthSessionExpired>(_onSessionExpired);
    _signInChanges = _auth.signInChanges.listen((_) => add(const AuthRefreshRequested()));
  }

  final AuthProvider _auth;
  final AuthRepository _repository;
  late final StreamSubscription<bool> _signInChanges;

  // AuthStarted and AuthRefreshRequested can arrive together (startup + Clerk
  // sign-in stream). Share one in-flight /auth/me request instead of racing.
  Future<AuthState>? _loadInFlight;

  Future<AuthState> _loadOnce() {
    final inFlight = _loadInFlight;
    if (inFlight != null) return inFlight;

    final request = _load();
    _loadInFlight = request;
    return request.whenComplete(() {
      if (identical(_loadInFlight, request)) _loadInFlight = null;
    });
  }

  Future<AuthState> _load() async {
    if (await _auth.accessToken() == null) return const AuthUnauthenticated();
    try {
      final profile = await _repository.me();
      if (!profile.isActive) return const AuthUnauthenticated(failure: ForbiddenFailure());
      return switch (profile.status) {
        AccountStatus.pendingApproval => AuthPending(profile),
        AccountStatus.noAccess => AuthNoAccess(profile),
        AccountStatus.active => Authenticated(profile),
      };
    } on Failure catch (failure) {
      return switch (failure) {
        UnauthorizedFailure() || ForbiddenFailure() => AuthUnauthenticated(failure: failure),
        _ => AuthUnavailable(failure),
      };
    }
  }

  Future<void> _onRefresh(AuthRefreshRequested event, Emitter<AuthState> emit) async {
    final before = state;
    // Desde el login no se pasa por la pantalla de carga: el formulario de Clerk sigue visible.
    if (before is! AuthUnauthenticated) emit(const AuthUnknown());
    final next = await _load();
    // Si ya estábamos sin sesión, un «sigue sin sesión» no borra el motivo (por ejemplo,
    // «tu sesión expiró»).
    if (before is AuthUnauthenticated && next is AuthUnauthenticated && next.failure == null) return;
    emit(next);
  }

  Future<void> _onSignOut(AuthSignOutRequested event, Emitter<AuthState> emit) async {
    await _auth.signOut();
    emit(const AuthUnauthenticated());
  }

  Future<void> _onSessionExpired(AuthSessionExpired event, Emitter<AuthState> emit) async {
    if (state is AuthUnauthenticated) return;
    emit(const AuthUnauthenticated(failure: UnauthorizedFailure()));
    await _auth.signOut();
  }

  @override
  Future<void> close() async {
    await _signInChanges.cancel();
    return super.close();
  }
}
