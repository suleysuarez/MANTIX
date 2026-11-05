import 'package:dio/dio.dart';
import '../../../core/auth/native_auth_provider.dart';

class MobileAuthRepository {
  MobileAuthRepository(this._dio, this._auth);
  final Dio _dio;
  final NativeAuthProvider _auth;

  Future<void> register({required String email, required String password}) async {
    await _dio.post('/mobile-auth/register', data: {'email': email, 'password': password});
  }

  Future<void> verifyEmail({required String email, required String code}) async {
    final response = await _dio.post<Map<String, dynamic>>('/mobile-auth/verify-email', data: {'email': email, 'code': code});
    await _auth.saveAccessToken(response.data!['access_token'] as String);
  }

  Future<void> login({required String email, required String password}) async {
    final response = await _dio.post<Map<String, dynamic>>('/mobile-auth/login', data: {'email': email, 'password': password});
    await _auth.saveAccessToken(response.data!['access_token'] as String);
  }

  Future<void> resendVerification(String email) async {
    await _dio.post('/mobile-auth/resend-verification', data: {'email': email});
  }

  Future<void> requestPasswordReset(String email) async {
    await _dio.post('/mobile-auth/forgot-password', data: {'email': email});
  }

  Future<void> resetPassword({required String email, required String code, required String newPassword}) async {
    await _dio.post('/mobile-auth/reset-password', data: {'email': email, 'code': code, 'new_password': newPassword});
  }
}
