import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/auth/clerk_auth_provider.dart';
import 'package:mantix/core/config/app_config.dart';

ClerkAuthProvider provider({
  bool signedIn = true,
  Future<String> Function()? jwt,
  void Function()? onRefresh,
  void Function()? onSignOut,
}) =>
    ClerkAuthProvider(
      isSignedIn: () => signedIn,
      jwt: jwt ?? () async => 'jwt-1',
      refresh: () async => onRefresh?.call(),
      signOut: () async => onSignOut?.call(),
    );

void main() {
  group('ClerkAuthProvider', () {
    test('sin sesión de Clerk no hay token y no se pide uno', () async {
      var asked = false;
      final auth = provider(signedIn: false, jwt: () async {
        asked = true;
        return 'x';
      });

      expect(await auth.accessToken(), isNull);
      expect(asked, isFalse);
    });

    test('con sesión devuelve el JWT vigente', () async {
      expect(await provider().accessToken(), 'jwt-1');
    });

    test('forceRefresh refresca el cliente antes de pedir el token', () async {
      final calls = <String>[];
      final auth = provider(
        onRefresh: () => calls.add('refresh'),
        jwt: () async {
          calls.add('jwt');
          return 'jwt-2';
        },
      );

      expect(await auth.accessToken(forceRefresh: true), 'jwt-2');
      expect(calls, ['refresh', 'jwt']);
    });

    test('si el SDK falla, devuelve null en vez de lanzar', () async {
      final auth = provider(jwt: () async => throw StateError('sin red'));

      expect(await auth.accessToken(), isNull);
    });

    test('cerrar sesión delega en Clerk', () async {
      var closed = false;

      await provider(onSignOut: () => closed = true).signOut();

      expect(closed, isTrue);
    });
  });

  group('AppConfig.hasClerk', () {
    test('solo acepta una clave publishable', () {
      expect(const AppConfig(apiBaseUrl: 'x', appVersion: '1').hasClerk, isFalse);
      expect(const AppConfig(apiBaseUrl: 'x', appVersion: '1', clerkPublishableKey: 'sk_test_123').hasClerk, isFalse);
      expect(const AppConfig(apiBaseUrl: 'x', appVersion: '1', clerkPublishableKey: 'pk_test_123').hasClerk, isTrue);
    });
  });
}
