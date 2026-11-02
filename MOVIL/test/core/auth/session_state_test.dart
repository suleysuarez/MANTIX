import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/auth/session_state.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  SessionState state() => container.read(sessionProvider);
  SessionNotifier notifier() => container.read(sessionProvider.notifier);

  test('starts unknown', () {
    expect(state(), isA<SessionUnknown>());
  });

  test('sign in and sign out', () {
    notifier().signIn();
    expect(state(), isA<SignedIn>());
    notifier().signOut();
    expect(state(), isA<SignedOut>());
    expect((state() as SignedOut).expired, isFalse);
  });

  test('expire signs out and says the session expired', () {
    notifier().signIn();
    notifier().expire();
    expect((state() as SignedOut).expired, isTrue);
  });

  test('expire several times in a row is harmless', () {
    notifier().signIn();
    var changes = 0;
    container.listen(sessionProvider, (_, _) => changes++);
    notifier()
      ..expire()
      ..expire()
      ..expire();
    expect(changes, 1);
  });

  test('a deliberate sign out is not turned into an expiry', () {
    notifier().signOut();
    notifier().expire();
    expect((state() as SignedOut).expired, isFalse);
  });
}
