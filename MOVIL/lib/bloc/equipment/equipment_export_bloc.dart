import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/equipment/export_models.dart';
import '../../repositories/equipment/equipment_repository.dart';
import '../../services/share_service.dart';
import '../../services/temp_file_service.dart';

part 'equipment_export_event.dart';
part 'equipment_export_state.dart';

/// Exporta el inventario: lo descarga en streaming a un archivo temporal, lo comparte con la
/// hoja de compartir del sistema y borra el temporal pase lo que pase.
class EquipmentExportBloc extends Bloc<EquipmentExportEvent, EquipmentExportState> {
  EquipmentExportBloc({required this._repository, required this._share, required this._tempFiles}) : super(const EquipmentExportState()) {
    on<EquipmentExportRequested>(_onRequested);
  }

  final EquipmentRepository _repository;
  final ShareService _share;
  final TempFileService _tempFiles;

  static String _two(int value) => value.toString().padLeft(2, '0');

  Future<void> _onRequested(EquipmentExportRequested event, Emitter<EquipmentExportState> emit) async {
    if (state.status == ExportStatus.working) return;
    emit(const EquipmentExportState(status: ExportStatus.working));
    final now = DateTime.now();
    final fileName = 'equipos-${now.year}-${_two(now.month)}-${_two(now.day)}.${event.format.extension}';
    String? path;
    try {
      path = await _tempFiles.createPath(fileName);
      var reported = 0.0;
      try {
        await _repository.downloadEquipmentReport(
          format: event.format.extension,
          savePath: path,
          statuses: event.statuses,
          typeId: event.typeId,
          onProgress: (progress) {
            // Se avisa cada 5 % para no repintar por cada trozo recibido.
            if (emit.isDone || (progress < 1 && progress - reported < 0.05)) return;
            reported = progress;
            emit(EquipmentExportState(status: ExportStatus.working, progress: progress));
          },
        );
      } catch (error) {
        final failure = toFailure(error);
        emit(EquipmentExportState(
          status: ExportStatus.failure,
          message: failure is ForbiddenFailure ? 'No tienes permiso para exportar el inventario.' : failure.message,
        ));
        return;
      }
      if (await _tempFiles.length(path) == 0) {
        emit(const EquipmentExportState(status: ExportStatus.empty, message: 'No hay equipos para exportar con estos filtros.'));
        return;
      }
      try {
        await _share.shareFile(path, mimeType: event.format.mimeType, subject: 'Inventario de equipos');
      } catch (_) {
        emit(const EquipmentExportState(status: ExportStatus.failure, message: 'No pudimos abrir la hoja de compartir.'));
        return;
      }
      emit(const EquipmentExportState(status: ExportStatus.shared));
    } catch (_) {
      emit(const EquipmentExportState(status: ExportStatus.failure, message: 'No pudimos preparar el archivo para exportar.'));
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
