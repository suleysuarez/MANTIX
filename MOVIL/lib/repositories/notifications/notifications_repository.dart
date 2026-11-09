import 'package:dio/dio.dart';

import '../../core/errors/failure_mapper.dart';
import '../../models/notifications/notification_models.dart';

/// Bandeja de notificaciones del usuario. Los errores salen como `Failure` ya traducido.
class NotificationsRepository {
  NotificationsRepository(this._dio);

  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (error) {
      throw mapDioException(error);
    }
  }

  Future<NotificationInbox> inbox() => _guard(() async {
        final response = await _dio.get<Map<String, Object?>>('/notifications');
        return NotificationInbox.fromJson(response.data!);
      });

  Future<void> markRead(int id) => _guard(() async {
        await _dio.post<Object?>('/notifications/$id/read');
      });

  Future<void> markAllRead() => _guard(() async {
        await _dio.post<Object?>('/notifications/read-all');
      });
}
