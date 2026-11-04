import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/failure.dart';
import 'clerk_auth_provider.dart';
import '../errors/failure_mapper.dart';
import '../network/providers.dart';
import 'user_profile.dart';

sealed class SessionState {
  const SessionState();
}

/// Sin sesión, o sesión que el servidor ya no acepta.
class SignedOut extends SessionState {
  const SignedOut({this.failure});
  final Failure? failure;
}

/// Sesión válida con el perfil local cargado.
class SignedIn extends SessionState {
  const SignedIn(this.profile);
  final UserProfile profile;
}

/// Hay token pero no pudimos cargar el perfil (red o servidor): se puede reintentar.
class SessionUnavailable extends SessionState {
  const SessionUnavailable(this.failure);
  final Failure failure;
}

class SessionController extends AsyncNotifier<SessionState> {
  @override
  Future<SessionState> build() {
    _reloadWhenClerkSignInChanges();
    return _load();
  }

  /// Cuando Clerk inicia o cierra sesión, se vuelve a cargar el perfil local.
  void _reloadWhenClerkSignInChanges() {
    final clerk = ref.read(clerkAuthStateProvider);
    if (clerk == null) return;
    var wasSignedIn = clerk.isSignedIn;
    void onChange() {
      if (clerk.isSignedIn == wasSignedIn) return;
      wasSignedIn = clerk.isSignedIn;
      refresh();
    }

    clerk.addListener(onChange);
    ref.onDispose(() => clerk.removeListener(onChange));
  }

  Future<SessionState> _load() async {
    final auth = ref.read(authProviderProvider);
    if (await auth.accessToken() == null) return const SignedOut();
    try {
      final response = await ref.read(apiClientProvider).get<Map<String, Object?>>('/auth/me');
      final profile = UserProfile.fromJson(response.data!);
      if (!profile.isActive) return const SignedOut(failure: ForbiddenFailure());
      return SignedIn(profile);
    } on DioException catch (error) {
      final failure = mapDioException(error);
      return switch (failure) {
        UnauthorizedFailure() || ForbiddenFailure() => SignedOut(failure: failure),
        _ => SessionUnavailable(failure),
      };
    }
  }

  /// Vuelve a cargar el perfil (tras iniciar sesión o al reintentar).
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await _load());
  }

  Future<void> signOut() async {
    await ref.read(authProviderProvider).signOut();
    state = const AsyncData(SignedOut());
  }
}

final sessionProvider = AsyncNotifierProvider<SessionController, SessionState>(SessionController.new);
