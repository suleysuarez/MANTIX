import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/errors/failure_mapper.dart';
import '../../models/equipment/equipment_models.dart';
import '../../models/page_info.dart';

/// Catálogo de equipos: listado paginado y contadores por estado. Cualquier error
/// de red o de servidor sale como un `Failure` ya traducido.
class EquipmentRepository {
  EquipmentRepository(this._dio);

  final Dio _dio;
  final _changes = StreamController<void>.broadcast();

  /// Emite cuando el catálogo cambia (por ejemplo, se registra un equipo): los listados se recargan solos.
  Stream<void> get changes => _changes.stream;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (error) {
      throw mapDioException(error);
    }
  }

  /// [statuses] es el valor del filtro `status` (lista separada por comas, ver
  /// [EquipmentGroup.filter]); [search] busca por etiqueta, serie, marca o modelo.
  Future<PagedResult<Equipment>> listEquipment({int page = 1, String? statuses, String? search}) => _guard(() async {
        final term = search?.trim();
        final response = await _dio.get<Object?>('/equipment', queryParameters: {
          'page': page,
          'size': PageInfo.defaultPageSize,
          'sort': '-created_at',
          if (statuses != null && statuses.isNotEmpty) 'status': statuses,
          if (term != null && term.isNotEmpty) 'search': term,
        });
        final data = response.data;
        return PagedResult(
          items: [if (data is List) for (final item in data) Equipment.fromJson((item as Map).cast<String, Object?>())],
          info: PageInfo.fromHeaders(response.headers),
        );
      });

  Future<EquipmentSummary> summary() => _guard(() async {
        final response = await _dio.get<Map<String, Object?>>('/equipment/summary');
        return EquipmentSummary.fromJson(response.data!);
      });

  Future<List<EquipmentType>> types() => _guard(() async {
        final response = await _dio.get<Object?>('/equipment/types');
        final data = response.data;
        return [if (data is List) for (final item in data) EquipmentType.fromJson((item as Map).cast<String, Object?>())];
      });

  /// Registra un equipo. Un 422 llega como `ValidationFailure` (errores por campo) y una etiqueta o
  /// serie repetida como `ConflictFailure` con el código `equipment_identifier_taken`.
  Future<Equipment> create(NewEquipment equipment) => _guard(() async {
        final response = await _dio.post<Map<String, Object?>>('/equipment', data: equipment.toJson());
        final created = Equipment.fromJson(response.data!);
        _changes.add(null);
        return created;
      });
}
