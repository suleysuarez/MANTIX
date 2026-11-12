import 'package:dio/dio.dart';

import '../../core/errors/failure_mapper.dart';
import '../../models/inventory/inventory_models.dart';
import '../../models/page_info.dart';

class InventoryRepository {
  InventoryRepository(this._dio);
  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (error) {
      throw mapDioException(error);
    }
  }

  Future<InventoryPage> listItems({int page = 1, int size = 10, String? search, String? category, String? status}) =>
      _guard(() async {
        final response = await _dio.get<Object?>('/inventory/items', queryParameters: {
          'page': page, 'size': size, 'sort': '-created_at',
          if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
          if (category != null && category.isNotEmpty) 'category': category,
          if (status != null && status.isNotEmpty) 'status': status,
        });
        final data = response.data;
        return InventoryPage(
          items: [if (data is List) for (final item in data) InventoryItem.fromJson((item as Map).cast<String, Object?>())],
          info: PageInfo.fromHeaders(response.headers),
        );
      });

  Future<InventoryOverview> overview({String period = '30d'}) => _guard(() async {
    final response = await _dio.get<Map<String, Object?>>('/inventory/overview', queryParameters: {'period': period});
    return InventoryOverview.fromJson(response.data!);
  });

  Future<List<InventoryOption>> options() => _guard(() async {
    final response = await _dio.get<Object?>('/inventory/options');
    final data = response.data;
    return [if (data is List) for (final item in data) InventoryOption.fromJson((item as Map).cast<String, Object?>())];
  });

  Future<InventoryItem> createItem(Map<String, Object?> payload) => _guard(() async {
    final response = await _dio.post<Map<String, Object?>>('/inventory/items', data: payload);
    return InventoryItem.fromJson(response.data!);
  });

  Future<InventoryItem> updateItem(int itemId, Map<String, Object?> payload) => _guard(() async {
    final response = await _dio.patch<Map<String, Object?>>('/inventory/items/$itemId', data: payload);
    return InventoryItem.fromJson(response.data!);
  });

  /// Historial de un ítem, del más reciente al más antiguo.
  Future<PagedResult<InventoryMovement>> movements(int itemId, {int page = 1, int size = PageInfo.defaultPageSize}) => _guard(() async {
    final response = await _dio.get<Object?>('/inventory/items/$itemId/movements', queryParameters: {'page': page, 'size': size});
    final data = response.data;
    return PagedResult(
      items: [if (data is List) for (final item in data) InventoryMovement.fromJson((item as Map).cast<String, Object?>())],
      info: PageInfo.fromHeaders(response.headers),
    );
  });

  Future<void> registerMovement(int itemId, {required String kind, required int quantity, String? notes}) => _guard(() async {
    await _dio.post<Object?>('/inventory/items/$itemId/movements', data: {
      'kind': kind, 'quantity': quantity,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
  });
}
