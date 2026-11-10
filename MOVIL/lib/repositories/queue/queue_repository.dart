import 'package:dio/dio.dart';

import '../../core/errors/failure_mapper.dart';
import '../../models/queue/queue_models.dart';

/// Resumen de la cola de solicitudes pendientes (`GET /maintenance/queue/summary`, requiere
/// `solicitudes:ver_todos`). Cualquier error sale como un `Failure` ya traducido.
class QueueRepository {
  QueueRepository(this._dio);

  final Dio _dio;

  /// [period] es `7d`, `30d` o `12m`; la bandeja usa los últimos 30 días.
  Future<QueueSummary> summary({String period = '30d'}) async {
    try {
      final response = await _dio.get<Map<String, Object?>>('/maintenance/queue/summary', queryParameters: {'period': period});
      return QueueSummary.fromJson(response.data!);
    } on DioException catch (error) {
      throw mapDioException(error);
    }
  }
}
