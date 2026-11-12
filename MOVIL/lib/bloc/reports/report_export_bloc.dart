import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../core/format/report_format.dart';
import '../../models/reports/report_models.dart';
import '../../repositories/reports/reports_repository.dart';
import '../../services/share_service.dart';
import '../../services/temp_file_service.dart';

part 'report_export_event.dart';
part 'report_export_state.dart';

/// Exporta un reporte: lo descarga en streaming a un archivo temporal, lo comparte con la hoja de
/// compartir del sistema y borra el temporal pase lo que pase. Solo hace una exportación a la vez.
class ReportExportBloc extends Bloc<ReportExportEvent, ReportExportState> {
  ReportExportBloc({required this._repository, required this._share, required this._tempFiles, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now,
        super(const ReportExportState()) {
    on<ReportExportRequested>(_onRequested);
    on<ReportExportDismissed>((_, emit) {
      if (state.status != ExportStatus.working) emit(const ReportExportState());
    });
  }

  final ReportsRepository _repository;
  final ShareService _share;
  final TempFileService _tempFiles;
  final DateTime Function() _clock;

  /// El motivo de un fallo de la descarga, en español y sin detalles internos.
  static String _messageOf(Failure failure) => switch (failure) {
        ForbiddenFailure() => 'No tienes permiso para exportar reportes.',
        ValidationFailure() => 'No se pudo generar el reporte con estos filtros. Acótalos e inténtalo de nuevo.',
        _ => failure.message,
      };

  Future<void> _onRequested(ReportExportRequested event, Emitter<ReportExportState> emit) async {
    if (state.status == ExportStatus.working) return;
    final definition = event.definition;
    final format = event.format;
    emit(const ReportExportState(status: ExportStatus.working));
    final fileName = reportFileName(definition.key, format, _clock());
    String? path;
    try {
      path = await _tempFiles.createPath(fileName);
      var reported = 0.0;
      try {
        await _repository.download(
          report: definition.key,
          format: format,
          filters: toApiFilters(definition, event.values),
          savePath: path,
          onProgress: (progress) {
            // Se avisa cada 5 % para no repintar por cada trozo recibido.
            if (emit.isDone || (progress < 1 && progress - reported < 0.05)) return;
            reported = progress;
            emit(ReportExportState(status: ExportStatus.working, progress: progress));
          },
        );
      } catch (error) {
        emit(ReportExportState(status: ExportStatus.failure, message: _messageOf(toFailure(error))));
        return;
      }
      if (await _tempFiles.length(path) == 0) {
        emit(const ReportExportState(status: ExportStatus.empty, message: 'No hay datos para exportar con estos filtros.'));
        return;
      }
      try {
        await _share.shareFile(path, mimeType: format.mimeType, subject: definition.title);
      } catch (_) {
        emit(const ReportExportState(status: ExportStatus.failure, message: 'No pudimos abrir la hoja de compartir.'));
        return;
      }
      emit(ReportExportState(status: ExportStatus.shared, fileName: fileName, format: format));
    } catch (_) {
      emit(const ReportExportState(status: ExportStatus.failure, message: 'No pudimos preparar el archivo para exportar.'));
    } finally {
      final created = path;
      if (created != null) {
        try {
          await _tempFiles.delete(created);
        } catch (_) {
          // El temporal vive en la caché de la app: si no se puede borrar ahora, el sistema lo hará.
        }
      }
    }
  }
}
