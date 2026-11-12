import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/errors/failure_mapper.dart';
import '../../models/page_info.dart';
import '../../models/reports/report_models.dart';

/// Acceso a la API de reportes: el catálogo, la vista previa, la descarga del archivo y el
/// historial de exportaciones. Cualquier error de red o de servidor sale como un `Failure` ya
/// traducido. Cada archivo generado avisa por [changes] para que el historial abierto se recargue.
class ReportsRepository {
  ReportsRepository(this._dio);

  final Dio _dio;
  final _changes = StreamController<void>.broadcast();

  /// Emite después de generar un reporte (queda en el historial).
  Stream<void> get changes => _changes.stream;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (error) {
      throw mapDioException(error);
    }
  }

  /// Los reportes con los filtros que acepta cada uno (requiere `reportes:ver`).
  Future<ReportCatalog> catalog() => _guard(() async {
        final response = await _dio.get<Map<String, Object?>>('/reports/catalog');
        return ReportCatalog.fromJson(response.data!);
      });

  /// Las primeras filas y el total (requiere `reportes:ver`). [filters] solo lleva lo que el
  /// reporte admite. Con [compare] pide también el periodo anterior (necesita las dos fechas).
  Future<ReportPreview> preview(String report, Map<String, Object?> filters, {bool compare = false}) => _guard(() async {
        final response = await _dio.post<Map<String, Object?>>('/reports/preview', data: {'report': report, 'filters': filters, 'compare': compare});
        return ReportPreview.fromJson(response.data!);
      });

  /// Exportaciones recientes, la más nueva primero (requiere `reportes:ver`).
  Future<PagedResult<ReportRun>> history({int page = 1, int size = 8}) => _guard(() async {
        final response = await _dio.get<Object?>('/reports/history', queryParameters: {'page': page, 'size': size});
        final data = response.data;
        return PagedResult(
          items: [if (data is List) for (final item in data) ReportRun.fromJson((item as Map).cast<String, Object?>())],
          info: PageInfo.fromHeaders(response.headers),
        );
      });

  /// Genera el reporte y lo descarga en streaming a [savePath] (`POST /reports/generate`, requiere
  /// `reportes:exportar`). Si el servidor lo rechaza no deja el archivo a medias.
  Future<void> download({required String report, required ReportFormat format, required Map<String, Object?> filters, required String savePath, void Function(double progress)? onProgress}) => _guard(() async {
        await _dio.download(
          '/reports/generate',
          savePath,
          data: {'report': report, 'format': format.extension, 'filters': filters},
          // El servidor arma el archivo antes de enviar el primer byte.
          options: Options(method: 'POST', receiveTimeout: const Duration(seconds: 120)),
          onReceiveProgress: (received, total) {
            if (total > 0) onProgress?.call(received / total);
          },
        );
        _changes.add(null);
      });
}
