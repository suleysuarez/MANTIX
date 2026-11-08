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

  /// Los tickets que el servidor deja ver a quien llama: para un Solicitante, los suyos.
  Future<PagedResult<TicketListItem>> listRequests({int page = 1, String? status}) => _guard(() async {
        final response = await _dio.get<Object?>('/maintenance/requests', queryParameters: {
          'page': page,
          'size': PageInfo.defaultPageSize,
          'sort': '-created_at',
          'status': ?status,
        });
        return PagedResult(
          items: _list(response.data, TicketListItem.fromJson),
          info: PageInfo.fromHeaders(response.headers),
        );
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
        return created;
      });

  /// Búsqueda parcial por etiqueta, serie, marca o modelo (el backend no tiene
  /// búsqueda exacta por etiqueta).
  Future<PagedResult<EquipmentOption>> searchEquipment({String? search, int page = 1}) => _guard(() async {
        final term = search?.trim();
        final response = await _dio.get<Object?>('/equipment', queryParameters: {
          'page': page,
          'size': PageInfo.defaultPageSize,
          if (term != null && term.isNotEmpty) 'search': term,
        });
        return PagedResult(
          items: _list(response.data, EquipmentOption.fromJson),
          info: PageInfo.fromHeaders(response.headers),
        );
      });
}
