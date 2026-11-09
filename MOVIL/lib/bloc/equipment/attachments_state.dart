part of 'attachments_bloc.dart';

/// Aviso de una sola vez para la interfaz (un archivo rechazado, una foto recuperada…). El `id`
/// cambia con cada aviso para que dos iguales seguidos también se muestren.
class AttachmentNotice extends Equatable {
  const AttachmentNotice({required this.id, required this.message, this.isError = true});

  final int id;
  final String message;
  final bool isError;

  @override
  List<Object?> get props => [id, message, isError];
}

class AttachmentsState extends Equatable {
  const AttachmentsState({
    this.drafts = const [],
    this.picking = false,
    this.uploading = false,
    this.equipmentId,
    this.notice,
  });

  final List<AttachmentDraft> drafts;

  /// Hay un selector (cámara, galería o documentos) abierto.
  final bool picking;
  final bool uploading;

  /// Equipo al que se suben los adjuntos (una vez creado).
  final int? equipmentId;
  final AttachmentNotice? notice;

  bool get isFull => drafts.length >= AttachmentRules.maxFiles;
  bool get hasFailed => drafts.any((draft) => draft.status == AttachmentStatus.failed);
  int get failedCount => drafts.where((draft) => draft.status == AttachmentStatus.failed).length;
  int get doneCount => drafts.where((draft) => draft.status == AttachmentStatus.done).length;
  bool get allDone => drafts.isNotEmpty && drafts.every((draft) => draft.status == AttachmentStatus.done);

  AttachmentsState copyWith({
    List<AttachmentDraft>? drafts,
    bool? picking,
    bool? uploading,
    int? equipmentId,
    AttachmentNotice? notice,
  }) =>
      AttachmentsState(
        drafts: drafts ?? this.drafts,
        picking: picking ?? this.picking,
        uploading: uploading ?? this.uploading,
        equipmentId: equipmentId ?? this.equipmentId,
        notice: notice ?? this.notice,
      );

  @override
  List<Object?> get props => [drafts, picking, uploading, equipmentId, notice];
}
