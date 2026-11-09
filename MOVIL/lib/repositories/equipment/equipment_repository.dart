import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/errors/failure_mapper.dart';
import '../../models/equipment/attachment_models.dart';
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
  Future<PagedResult<Equipment>> listEquipment({int page = 1, int size = PageInfo.defaultPageSize, String? statuses, String? search, int? typeId}) => _guard(() async {
        final term = search?.trim();
        final response = await _dio.get<Object?>('/equipment', queryParameters: {
          'page': page,
          'size': size,
          'sort': '-created_at',
          if (statuses != null && statuses.isNotEmpty) 'status': statuses,
          'equipment_type_id': ?typeId,
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

  Future<List<EquipmentLocation>> locations() => _guard(() async {
        final response = await _dio.get<Object?>('/locations');
        final data = response.data;
        return [if (data is List) for (final item in data) EquipmentLocation.fromJson((item as Map).cast<String, Object?>())];
      });

  /// Usuarios activos cuyo nombre o correo contiene [search] (máximo 20; requiere `equipos:asignar`).
  Future<List<CustodianCandidate>> custodianCandidates(String? search) => _guard(() async {
        final term = search?.trim();
        final response = await _dio.get<Object?>('/equipment/custodian-candidates', queryParameters: {
          if (term != null && term.isNotEmpty) 'search': term,
        });
        final data = response.data;
        return [if (data is List) for (final item in data) CustodianCandidate.fromJson((item as Map).cast<String, Object?>())];
      });

  /// Coloca el equipo en una ubicación (requiere `equipos:editar`).
  Future<void> assignLocation(int equipmentId, int locationId) => _guard(() async {
        await _dio.post<Object?>('/equipment/$equipmentId/location', data: {'location_id': locationId});
        _changes.add(null);
      });

  /// Deja el equipo a cargo de un usuario (requiere `equipos:asignar`).
  Future<void> assignCustody(int equipmentId, int userId) => _guard(() async {
        await _dio.post<Object?>('/equipment/$equipmentId/custody', data: {'assigned_to_user_id': userId});
        _changes.add(null);
      });

  static String _mimeType(String fileName) => switch (AttachmentRules.extensionOf(fileName)) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'pdf' => 'application/pdf',
        _ => 'text/plain',
      };

  /// Sube un adjunto del equipo (requiere `equipos:adjuntar`). El archivo se envía desde su
  /// ruta, por partes, sin cargarlo entero en memoria; [onProgress] recibe de 0 a 1. Un 413
  /// (demasiado grande) o un 415 (tipo no admitido) llegan como `ValidationFailure`.
  Future<void> uploadAttachment(int equipmentId, AttachmentFile file, {void Function(double progress)? onProgress}) => _guard(() async {
        final form = FormData.fromMap({
          'file': await MultipartFile.fromFile(file.path, filename: sanitizeFileName(file.name), contentType: DioMediaType.parse(_mimeType(file.name))),
        });
        await _dio.post<Object?>(
          '/equipment/$equipmentId/attachments',
          data: form,
          onSendProgress: (sent, total) {
            if (total > 0) onProgress?.call(sent / total);
          },
        );
      });

  /// Descarga el inventario (`GET /reports/equipment`, requiere `reportes:exportar`) en
  /// streaming a [savePath]. [format] es `xlsx`, `csv` o `pdf`; el filtro de estado y el de
  /// categoría se aplican, el de texto no existe en el servidor.
  Future<void> downloadEquipmentReport({
    required String format,
    required String savePath,
    String? statuses,
    int? typeId,
    void Function(double progress)? onProgress,
  }) => _guard(() async {
        await _dio.download(
          '/reports/equipment',
          savePath,
          queryParameters: {
            'format': format,
            if (statuses != null && statuses.isNotEmpty) 'status': statuses,
            'equipment_type_id': ?typeId,
          },
          // El servidor genera el archivo antes de enviar el primer byte.
          options: Options(receiveTimeout: const Duration(seconds: 120)),
          onReceiveProgress: (received, total) {
            if (total > 0) onProgress?.call(received / total);
          },
        );
      });
}
