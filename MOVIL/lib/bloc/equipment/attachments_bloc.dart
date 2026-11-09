import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure_mapper.dart';
import '../../models/equipment/attachment_models.dart';
import '../../repositories/equipment/equipment_repository.dart';
import '../../services/file_picker_service.dart';
import '../../services/image_picker_service.dart';

part 'attachments_event.dart';
part 'attachments_state.dart';

/// Adjuntos del formulario «Nuevo equipo»: elegir (cámara, galería o documento), validar,
/// y, una vez creado el equipo, subirlos uno a uno con su progreso. Si alguna subida falla el
/// equipo se queda como está y solo se reintentan los fallidos.
class AttachmentsBloc extends Bloc<AttachmentsEvent, AttachmentsState> {
  AttachmentsBloc({required this._repository, required this._images, required this._files}) : super(const AttachmentsState()) {
    on<AttachmentPickRequested>(_onPick);
    on<LostPhotoRecoveryRequested>(_onRecover);
    on<AttachmentRemoved>(_onRemoved);
    on<AttachmentsUploadRequested>((event, emit) => _upload(event.equipmentId, emit));
    on<AttachmentsRetryRequested>((event, emit) async {
      final equipmentId = state.equipmentId;
      if (equipmentId != null) await _upload(equipmentId, emit);
    });
  }

  final EquipmentRepository _repository;
  final ImagePickerService _images;
  final FilePickerService _files;
  int _nextDraftId = 1;
  int _nextNoticeId = 1;

  AttachmentsState _noticed(AttachmentsState from, String message, {bool isError = true}) =>
      from.copyWith(notice: AttachmentNotice(id: _nextNoticeId++, message: message, isError: isError));

  Future<void> _onPick(AttachmentPickRequested event, Emitter<AttachmentsState> emit) async {
    if (state.picking || state.uploading) return;
    if (state.isFull) {
      emit(_noticed(state, 'Ya adjuntaste el máximo de ${AttachmentRules.maxFiles} archivos.'));
      return;
    }
    emit(state.copyWith(picking: true));
    final AttachmentFile? file;
    try {
      file = switch (event.source) {
        AttachmentSource.camera => await _images.takePhoto(),
        AttachmentSource.gallery => await _images.pickFromGallery(),
        AttachmentSource.document => await _files.pickDocument(),
      };
    } catch (_) {
      final what = switch (event.source) {
        AttachmentSource.camera => 'la cámara',
        AttachmentSource.gallery => 'la galería',
        AttachmentSource.document => 'el selector de archivos',
      };
      emit(_noticed(state.copyWith(picking: false), 'No pudimos abrir $what. Inténtalo de nuevo.'));
      return;
    }
    // Cancelar el selector no es un error: no hay nada que avisar.
    if (file == null) {
      emit(state.copyWith(picking: false));
      return;
    }
    emit(_withFile(state.copyWith(picking: false), file, event.source));
  }

  Future<void> _onRecover(LostPhotoRecoveryRequested event, Emitter<AttachmentsState> emit) async {
    try {
      final file = await _images.recoverLostPhoto();
      if (file == null) return;
      emit(_withFile(state, file, AttachmentSource.camera, recovered: true));
    } catch (_) {
      // Recuperar es un extra: si falla, el formulario sigue como si nada.
    }
  }

  AttachmentsState _withFile(AttachmentsState from, AttachmentFile file, AttachmentSource source, {bool recovered = false}) {
    final problem = AttachmentRules.validate(file, source);
    if (problem != null) return _noticed(from, '«${file.name}»: $problem');
    if (from.drafts.any((draft) => draft.file.path == file.path)) return _noticed(from, 'Ese archivo ya está en la lista.');
    if (from.isFull) return _noticed(from, 'Ya adjuntaste el máximo de ${AttachmentRules.maxFiles} archivos.');
    final next = from.copyWith(drafts: [...from.drafts, AttachmentDraft(id: _nextDraftId++, file: file)]);
    return recovered ? _noticed(next, 'Recuperamos la foto que estabas tomando.', isError: false) : next;
  }

  void _onRemoved(AttachmentRemoved event, Emitter<AttachmentsState> emit) {
    if (state.uploading) return;
    final target = state.drafts.where((draft) => draft.id == event.id).firstOrNull;
    // Lo ya subido no se quita de la lista: el equipo ya lo tiene.
    if (target == null || target.status == AttachmentStatus.done) return;
    emit(state.copyWith(drafts: [for (final draft in state.drafts) if (draft.id != event.id) draft]));
  }

  AttachmentsState _updated(int id, AttachmentDraft Function(AttachmentDraft draft) change) =>
      state.copyWith(drafts: [for (final draft in state.drafts) draft.id == id ? change(draft) : draft]);

  Future<void> _upload(int equipmentId, Emitter<AttachmentsState> emit) async {
    if (state.uploading) return;
    final targets = [
      for (final draft in state.drafts)
        if (draft.status == AttachmentStatus.pending || draft.status == AttachmentStatus.failed) draft.id,
    ];
    if (targets.isEmpty) return;
    emit(state.copyWith(uploading: true, equipmentId: equipmentId));
    for (final id in targets) {
      emit(_updated(id, (draft) => draft.copyWith(status: AttachmentStatus.uploading, progress: 0, clearFailure: true)));
      final file = state.drafts.firstWhere((draft) => draft.id == id).file;
      var reported = 0.0;
      try {
        await _repository.uploadAttachment(equipmentId, file, onProgress: (progress) {
          // Se avisa cada 5 % para no repintar por cada trozo enviado.
          if (emit.isDone || (progress < 1 && progress - reported < 0.05)) return;
          reported = progress;
          emit(_updated(id, (draft) => draft.copyWith(progress: progress)));
        });
        emit(_updated(id, (draft) => draft.copyWith(status: AttachmentStatus.done, progress: 1)));
      } catch (error) {
        emit(_updated(id, (draft) => draft.copyWith(status: AttachmentStatus.failed, failureMessage: toFailure(error).message)));
      }
    }
    emit(state.copyWith(uploading: false));
    if (!state.hasFailed) {
      try {
        await _files.clearTemporaryFiles();
      } catch (_) {
        // Limpiar la caché es un extra.
      }
    }
  }
}
