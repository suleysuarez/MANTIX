import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/errors/failure_mapper.dart';
import '../../models/page_info.dart';
import '../../models/requests/request_models.dart';

/// Acceso a la API de solicitudes y equipos. Cualquier error de red o de servidor
/// sale como un `Failure` ya traducido.
class RequestsRepository {
  RequestsRepository(this._dio);

  final Dio _dio;
  final _changes = StreamController<void>.broadcast();
  final _created = StreamController<int>.broadcast();

  /// Emite el id del ticket recién creado: los listados vuelven a la página 1 y lo resaltan.
  Stream<int> get created => _created.stream;

  /// Avisa cuando la app cambia datos de solicitudes (hoy, al crear una), para que
  /// los listados abiertos se recarguen sin acoplarse a quien creó el cambio.
  Stream<void> get changes => _changes.stream;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (error) {
      throw mapDioException(error);
    }
  }

  List<T> _list<T>(Object? data, T Function(Map<String, Object?>) parse) {
    if (data is! List) return const [];
    return [for (final item in data) parse((item as Map).cast<String, Object?>())];
  }

  /// Los tickets que el servidor deja ver a quien llama, acotados por sus permisos.
  Future<PagedResult<TicketListItem>> listRequests({int page = 1, String? status, String? search, DateTime? dateFrom, DateTime? dateTo, int? equipmentId, List<int> equipmentIds = const [], List<String> priorities = const [], int size = PageInfo.defaultPageSize}) => _guard(() async {
        final term = search?.trim();
        final response = await _dio.get<Object?>('/maintenance/requests', queryParameters: {
          'page': page,
          'size': size,
          'sort': '-created_at',
          'status': ?status,
          // Un solo valor viaja como siempre; varios (prioridades separadas por coma, equipos con
          // el parámetro repetido) los entiende un servidor que admite listas.
          'equipment_id': ?(equipmentIds.length > 1 ? equipmentIds : (equipmentIds.length == 1 ? equipmentIds.first : equipmentId)),
          if (priorities.isNotEmpty) 'priority': priorities.join(','),
          if (term != null && term.isNotEmpty) 'search': term,
          if (dateFrom != null) 'date_from': dateFrom.toUtc().toIso8601String(),
          if (dateTo != null) 'date_to': dateTo.add(const Duration(days: 1)).subtract(const Duration(microseconds: 1)).toUtc().toIso8601String(),
        });
        return PagedResult(
          items: _list(response.data, TicketListItem.fromJson),
          info: PageInfo.fromHeaders(response.headers),
        );
      });

  /// Cambia el estado de un ticket. [notes] y [resolutionSummary] son los datos que algunos
  /// estados exigen (resolución al resolver, motivo al cancelar).
  Future<void> transitionStatus(int id, String status, {String? notes, String? resolutionSummary}) => _guard(() async {
        await _dio.post<Object?>('/maintenance/requests/$id/status', data: {
          'status': status,
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
          if (resolutionSummary != null && resolutionSummary.trim().isNotEmpty) 'resolution_summary': resolutionSummary.trim(),
        });
        _changes.add(null);
      });

  /// Estados del flujo, en orden, con sus transiciones válidas y los datos que exigen.
  Future<List<WorkflowStatus>> workflow() => _guard(() async {
        final response = await _dio.get<Object?>('/maintenance/requests/workflow');
        return _list(response.data, WorkflowStatus.fromJson)..sort((a, b) => a.order.compareTo(b.order));
      });

  Future<TicketDetail> getRequest(int id) => _guard(() async {
        final response = await _dio.get<Map<String, Object?>>('/maintenance/requests/$id');
        return TicketDetail.fromJson(response.data!);
      });

  Future<List<Attachment>> listAttachments(int requestId) => _guard(() async {
        final response = await _dio.get<Object?>('/maintenance/requests/$requestId/attachments');
        return _list(response.data, Attachment.fromJson);
      });

  Future<TicketDetail> create(NewRequest request) => _guard(() async {
        final response = await _dio.post<Map<String, Object?>>('/maintenance/requests', data: request.toJson());
        final created = TicketDetail.fromJson(response.data!);
        _changes.add(null);
        _created.add(created.id);
        return created;
      });

  /// Búsqueda parcial por etiqueta, serie, marca o modelo.
  Future<PagedResult<EquipmentOption>> searchEquipment({String? search, int page = 1, int size = PageInfo.defaultPageSize}) => _guard(() async {
        final term = search?.trim();
        final response = await _dio.get<Object?>('/equipment', queryParameters: {
          'page': page,
          'size': size,
          if (term != null && term.isNotEmpty) 'search': term,
        });
        return PagedResult(
          items: _list(response.data, EquipmentOption.fromJson),
          info: PageInfo.fromHeaders(response.headers),
        );
      });
}
