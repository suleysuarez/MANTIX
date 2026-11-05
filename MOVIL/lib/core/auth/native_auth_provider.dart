import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'auth_provider.dart';

/// Stores Mantix's short-lived mobile access token in Android Keystore/iOS Keychain.
class NativeAuthProvider implements AuthProvider {
  NativeAuthProvider({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'mantix_mobile_access_token';
  final FlutterSecureStorage _storage;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  @override
  Future<String?> accessToken({bool forceRefresh = false}) {
    // This first version has no refresh-token endpoint. A forced refresh means
    // the access token was rejected, so let the API client expire the session.
    if (forceRefresh) return Future.value(null);
    return _storage.read(key: _tokenKey);
  }

  Future<void> saveAccessToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
    _changes.add(true);
  }

  @override
  Future<void> signOut() async {
    await _storage.delete(key: _tokenKey);
    _changes.add(false);
  }

  @override
  Stream<bool> get signInChanges => _changes.stream;
}
