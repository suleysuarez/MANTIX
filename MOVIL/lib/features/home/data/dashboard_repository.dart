import 'package:dio/dio.dart';

class DashboardRepository {
  DashboardRepository(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> _get(String path, [Map<String, dynamic>? query]) async {
    final response = await _dio.get<Map<String, dynamic>>(path, queryParameters: query);
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> loadKpis(String period) => _get('/dashboard/kpis', {'period': period});
  Future<Map<String, dynamic>> loadTrends(String period) => _get('/dashboard/trends', {'period': period});
  Future<Map<String, dynamic>> loadAlerts() => _get('/dashboard/alerts');
  Future<Map<String, dynamic>> loadTopEquipment(String period) {
    final days = switch (period) {'7d' => 7, '12m' => 365, _ => 30};
    return _get('/dashboard/top-failing-equipment', {'days': days, 'limit': 5});
  }
}
