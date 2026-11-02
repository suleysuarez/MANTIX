import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether there is a signed-in person. The effective permissions arrive with `/auth/me` and
/// live in `core/permissions`.
sealed class SessionState {
  const SessionState();
}

/// The app has just started and has not checked for a stored session yet.
final class SessionUnknown extends SessionState {
  const SessionUnknown();
}

final class SignedOut extends SessionState {
  /// `true` when the session ended by itself (the token could not be renewed), so the login
  /// screen can say so.
  const SignedOut({this.expired = false});

  final bool expired;
}

final class SignedIn extends SessionState {
  const SignedIn();
}

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() => const SessionUnknown();

  void signIn() => state = const SignedIn();

  void signOut() => state = const SignedOut();

  /// Safe to call several times in a row: a burst of failed requests expires the session once.
  void expire() {
    if (state is! SignedOut) state = const SignedOut(expired: true);
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(
  SessionNotifier.new,
);
