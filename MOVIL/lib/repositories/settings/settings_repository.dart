import 'package:dio/dio.dart';

import '../../core/errors/failure_mapper.dart';
import '../../models/settings/settings_models.dart';

class SettingsRepository {
  SettingsRepository(this._dio);
  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try { return await call(); } on DioException catch (error) { throw mapDioException(error); }
  }

  List<T> _list<T>(Object? data, T Function(Map<String, Object?>) parse) => [
    if (data is List) for (final item in data) if (item is Map) parse(item.cast<String, Object?>()),
  ];

  Future<SystemHealth> health() => _guard(() async {
    final response = await _dio.get<Map<String, Object?>>('/settings/health');
    return SystemHealth.fromJson(response.data!);
  });
  Future<List<CategoryAdmin>> categories() => _guard(() async {
    final response = await _dio.get<Object?>('/settings/categories');
    return _list(response.data, CategoryAdmin.fromJson);
  });
  Future<OrganizationSettings> organization() => _guard(() async {
    final response = await _dio.get<Map<String, Object?>>('/settings/organization');
    return OrganizationSettings.fromJson(response.data!);
  });
  Future<List<PriorityAdmin>> priorities() => _guard(() async {
    final response = await _dio.get<Object?>('/priorities', queryParameters: {'include_inactive': true});
    return _list(response.data, PriorityAdmin.fromJson);
  });
  Future<void> saveOrganization(String companyName) => _guard(() async {
    await _dio.put<Object?>('/settings/organization', data: {'company_name': companyName});
  });
  Future<void> createCategory({required String code, required String name}) => _guard(() async {
    await _dio.post<Object?>('/settings/categories', data: {'code': code, 'name': name});
  });
  Future<void> updateCategory(int id, {String? name, bool? isActive}) => _guard(() async {
    await _dio.patch<Object?>('/settings/categories/$id', data: {'name': ?name, 'is_active': ?isActive});
  });
  Future<void> deleteCategory(int id) => _guard(() async { await _dio.delete<Object?>('/settings/categories/$id'); });
  Future<void> updatePriority(int id, {String? name, int? level, int? slaHours, bool clearSla = false, bool? isActive}) => _guard(() async {
    await _dio.patch<Object?>('/priorities/$id', data: {
      'name': ?name, 'level': ?level,
      if (clearSla) 'sla_hours': null else 'sla_hours': ?slaHours,
      'is_active': ?isActive,
    });
  });
}
