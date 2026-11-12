import 'package:dio/dio.dart';
import '../../services/native_auth_provider.dart';

class MobileAuthRepository {
  MobileAuthRepository(this._dio, this._auth);
  final Dio _dio;
  final NativeAuthProvider _auth;

  /// Crea la cuenta. No hay código ni correo que verificar: quien la crea inicia sesión enseguida
  /// con [login]. La cuenta empieza sin rol y un administrador debe aprobarla.
  Future<void> register({required String email, required String password, required String firstName, String? lastName}) async {
    await _dio.post('/mobile-auth/register', data: {'email': email, 'password': password, 'first_name': firstName, if (lastName != null && lastName.isNotEmpty) 'last_name': lastName});
  }

  Future<void> login({required String email, required String password}) async {
    final response = await _dio.post<Map<String, dynamic>>('/mobile-auth/login', data: {'email': email, 'password': password});
    await _auth.saveAccessToken(response.data!['access_token'] as String);
  }
}
