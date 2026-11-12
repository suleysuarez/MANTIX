import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/errors/failure_mapper.dart';
import '../../models/equipment/attachment_models.dart';
import '../../models/page_info.dart';
import '../../models/profile/profile_models.dart';

/// Mi perfil (`/profile`): datos, foto y actividad. Todo actúa sobre la persona con sesión; no hay
/// ningún id en las rutas. Cualquier error sale como un `Failure` ya traducido.
class ProfileRepository {
  ProfileRepository(this._dio);

  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (error) {
      throw mapDioException(error);
    }
  }

  /// Requiere `perfil:ver`.
  Future<ProfileData> get() => _guard(() async {
        final response = await _dio.get<Map<String, Object?>>('/profile');
        return ProfileData.fromJson(response.data!);
      });

  /// Cambia el nombre y/o el teléfono (requiere `perfil:editar`). Solo viaja lo que se pasa: un
  /// teléfono vacío lo borra. El correo no se envía nunca: es la identidad de acceso.
  Future<ProfileData> update({String? fullName, String? phone}) => _guard(() async {
        final response = await _dio.patch<Map<String, Object?>>('/profile', data: {
          'full_name': ?fullName,
          'phone': ?phone,
        });
        return ProfileData.fromJson(response.data!);
      });

  /// Los bytes de mi foto (JPEG de 256×256). La petición lleva el token, por eso no se usa una URL.
  Future<Uint8List> avatar() => _guard(() async {
        final response = await _dio.get<List<int>>('/profile/avatar', options: Options(responseType: ResponseType.bytes));
        return Uint8List.fromList(response.data!);
      });

  /// Sube mi foto (requiere `perfil:editar`): PNG o JPEG de hasta 2 MB y de 64×64 como mínimo.
  /// El servidor la recorta cuadrada. Un 413 o un 415 llegan como `ValidationFailure`.
  Future<ProfileData> uploadAvatar(AttachmentFile file) => _guard(() async {
        final isPng = file.name.toLowerCase().endsWith('.png');
        final form = FormData.fromMap({
          'file': await MultipartFile.fromFile(file.path, filename: file.name, contentType: DioMediaType.parse(isPng ? 'image/png' : 'image/jpeg')),
        });
        final response = await _dio.put<Map<String, Object?>>('/profile/avatar', data: form);
        return ProfileData.fromJson(response.data!);
      });

  Future<ProfileData> removeAvatar() => _guard(() async {
        final response = await _dio.delete<Map<String, Object?>>('/profile/avatar');
        return ProfileData.fromJson(response.data!);
      });

  /// Mi actividad, la más reciente primero (requiere `perfil:ver`).
  Future<PagedResult<HistoryEntry>> history({int page = 1, int size = PageInfo.defaultPageSize}) => _guard(() async {
        final response = await _dio.get<Object?>('/profile/history', queryParameters: {'page': page, 'size': size});
        final data = response.data;
        return PagedResult(
          items: [if (data is List) for (final item in data) HistoryEntry.fromJson((item as Map).cast<String, Object?>())],
          info: PageInfo.fromHeaders(response.headers),
        );
      });
}
