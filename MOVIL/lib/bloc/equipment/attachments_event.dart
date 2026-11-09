part of 'attachments_bloc.dart';

sealed class AttachmentsEvent {
  const AttachmentsEvent();
}

/// Abre la cámara, la galería o el selector de documentos y añade lo elegido si es válido.
class AttachmentPickRequested extends AttachmentsEvent {
  const AttachmentPickRequested(this.source);

  final AttachmentSource source;
}

/// Si Android cerró la app mientras se tomaba una foto, la recupera al volver.
class LostPhotoRecoveryRequested extends AttachmentsEvent {
  const LostPhotoRecoveryRequested();
}

/// Quita un adjunto que todavía no se ha subido.
class AttachmentRemoved extends AttachmentsEvent {
  const AttachmentRemoved(this.id);

  final int id;
}

/// Sube los adjuntos pendientes al equipo recién creado.
class AttachmentsUploadRequested extends AttachmentsEvent {
  const AttachmentsUploadRequested(this.equipmentId);

  final int equipmentId;
}

/// Vuelve a subir solo los adjuntos que fallaron.
class AttachmentsRetryRequested extends AttachmentsEvent {
  const AttachmentsRetryRequested();
}
