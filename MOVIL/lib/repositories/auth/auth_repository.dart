import 'package:dio/dio.dart';

import '../../core/errors/failure_mapper.dart';
import '../../models/auth/user_profile.dart';

/// Acceso a `GET /auth/me` y al cierre de sesión en el servidor. Cualquier error de red o de servidor sale como un
/// `Failure` ya traducido.
class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;

  /// Perfil local con roles y permisos efectivos de la sesión actual.
  Future<UserProfile> me() async {
    try {
      final response = await _dio.get<Map<String, Object?>>('/auth/me');
      return UserProfile.fromJson(response.data!);
    } on DioException catch (error) {
      throw mapDioException(error);
    }
  }

  /// Revoca en el servidor todos los tokens de la cuenta (`POST /mobile-auth/logout`),
  /// en todos los dispositivos. Es de mejor esfuerzo: sin red, con un error del servidor
  /// o con un token que ya no sirve, no lanza nada, porque el cierre local no debe
  /// depender de esta llamada. Espera como máximo 5 segundos.
  Future<void> revokeSession() async {
    try {
      await _dio
          .post<Object?>('/mobile-auth/logout')
          .timeout(const Duration(seconds: 5));
    } on Object {
      // Se ignora a propósito: el token local se borra de todos modos.
    }
  }
}
