import 'package:dio/dio.dart';

import '../errors/failure_mapper.dart';
import 'user_profile.dart';

/// Acceso a `GET /auth/me`. Cualquier error de red o de servidor sale como un
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
}
