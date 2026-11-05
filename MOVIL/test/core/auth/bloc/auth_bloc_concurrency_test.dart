import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/auth/auth_provider.dart';
import 'package:mantix/core/auth/auth_repository.dart';
import 'package:mantix/core/auth/bloc/auth_bloc.dart';
import 'package:mantix/core/auth/user_profile.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthProvider extends Mock implements AuthProvider {}

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthProvider auth;
  late MockAuthRepository repository;
  const profile = UserProfile(
    id: 7,
    email: 'admin@example.com',
    fullName: 'Mantix Admin',
    isActive: true,
    roles: ['ADMIN'],
    permissions: {'users.manage'},
  );

  setUp(() {
    auth = MockAuthProvider();
    repository = MockAuthRepository();
    when(() => auth.signInChanges).thenAnswer((_) => const Stream<bool>.empty());
    when(() => auth.accessToken()).thenAnswer((_) async => 'valid-token');
    when(() => auth.signOut()).thenAnswer((_) async {});
    when(() => repository.me()).thenAnswer((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return profile;
    });
  });

  blocTest<AuthBloc, AuthState>(
    'shares one /auth/me request when startup and refresh arrive together',
    build: () => AuthBloc(auth: auth, repository: repository),
    act: (bloc) {
      bloc.add(const AuthStarted());
      bloc.add(const AuthRefreshRequested());
    },
    wait: const Duration(milliseconds: 100),
    expect: () => [const Authenticated(profile)],
    verify: (_) {
      verify(() => auth.accessToken()).called(2);
      verify(() => repository.me()).called(1);
    },
  );
}
