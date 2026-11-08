import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../errors/failure.dart';
import '../../../services/auth_provider.dart';
import '../../../repositories/auth/auth_repository.dart';
import '../../../models/auth/user_profile.dart';

part 'auth_event.dart';
part 'auth_state.dart';

/// Sesión de la app. El proveedor nativo guarda el token y este Bloc resuelve
/// el perfil, los roles y los permisos devueltos por `/auth/me`.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required AuthProvider auth, required AuthRepository repository}) : _auth = auth, _repository = repository, super(const AuthUnknown()) {
    on<AuthStarted>((_, emit) async => emit(await _load()));
    on<AuthRefreshRequested>(_onRefresh);
    on<AuthSignOutRequested>(_onSignOut);
    on<AuthSessionExpired>(_onSessionExpired);
    _signInChanges = _auth.signInChanges.listen((_) => add(const AuthRefreshRequested()));
  }

  final AuthProvider _auth;
  final AuthRepository _repository;
  late final StreamSubscription<bool> _signInChanges;

  // Startup and a native sign-in event can both reach /auth/me at once.
  // Keep token checks independent, but share the in-flight profile request so
  // a login event arriving during startup is not hidden by an earlier null token.
  Future<UserProfile>? _profileInFlight;

  Future<UserProfile> _loadProfileOnce() {
    final inFlight = _profileInFlight;
    if (inFlight != null) return inFlight;

    final request = _repository.me();
    _profileInFlight = request;
    return request.whenComplete(() {
      if (identical(_profileInFlight, request)) _profileInFlight = null;
    });
  }

  Future<AuthState> _load() async {
    if (await _auth.accessToken() == null) return const AuthUnauthenticated();
    try {
      final profile = await _loadProfileOnce();
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
    // Mantén visible el formulario mientras el usuario no haya iniciado sesión.
    if (before is! AuthUnauthenticated && before is! AuthUnknown) {
      emit(const AuthUnknown());
    }
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
