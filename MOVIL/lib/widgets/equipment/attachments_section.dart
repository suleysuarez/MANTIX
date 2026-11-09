import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/equipment/attachments_bloc.dart';
import '../../core/format/formatters.dart';
import '../../core/theme/app_colors.dart';
import '../../models/equipment/attachment_models.dart';

IconData _iconFor(String fileName) =>
    switch (AttachmentRules.extensionOf(fileName)) {
      'jpg' || 'jpeg' || 'png' => Icons.image_outlined,
      'pdf' => Icons.picture_as_pdf_outlined,
      _ => Icons.description_outlined,
    };

/// Hoja «Adjuntar» con las tres formas de añadir un archivo. Las dos primeras usan fotos
/// (JPG o PNG); la tercera, documentos (PDF o TXT).
Future<void> showAttachSheet(BuildContext context) {
  final bloc = context.read<AttachmentsBloc>();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      void choose(AttachmentSource source) {
        Navigator.of(sheetContext).pop();
        bloc.add(AttachmentPickRequested(source));
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Adjuntar',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            ListTile(
              key: const Key('attach-camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => choose(AttachmentSource.camera),
            ),
            ListTile(
              key: const Key('attach-gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              subtitle: const Text('Solo JPG o PNG'),
              onTap: () => choose(AttachmentSource.gallery),
            ),
            ListTile(
              key: const Key('attach-document'),
              leading: const Icon(Icons.attach_file_rounded),
              title: const Text('Elegir un archivo'),
              subtitle: const Text('PDF o TXT'),
              onTap: () => choose(AttachmentSource.document),
            ),
          ],
        ),
      );
    },
  );
}

/// Sección «Adjuntos» del formulario: botón para añadir y lista de lo elegido, con quitar.
class AttachmentsSection extends StatelessWidget {
  const AttachmentsSection({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<AttachmentsBloc, AttachmentsState>(
    builder: (context, state) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: const Key('attach-button'),
          borderRadius: BorderRadius.circular(14),
          onTap: enabled && !state.picking && !state.isFull
              ? () => showAttachSheet(context)
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.grey),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (state.picking)
                  const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(
                    Icons.add_a_photo_outlined,
                    color: AppColors.steel,
                    size: 20,
                  ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    state.isFull
                        ? 'Máximo de ${AttachmentRules.maxFiles} archivos'
                        : 'Adjuntar fotos o archivos',
                    style: const TextStyle(
                      color: AppColors.steel,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 2),
          child: Text(
            '${state.drafts.length}/${AttachmentRules.maxFiles} · JPG, PNG, PDF o TXT · hasta 10 MB cada uno',
            key: const Key('attach-counter'),
            style: const TextStyle(color: AppColors.slate, fontSize: 11),
          ),
        ),
        for (final draft in state.drafts)
          _DraftTile(
            draft: draft,
            onRemove: enabled && !state.uploading
                ? () => context.read<AttachmentsBloc>().add(
                    AttachmentRemoved(draft.id),
                  )
                : null,
          ),
      ],
    ),
  );
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({required this.draft, this.onRemove});

  final AttachmentDraft draft;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(_iconFor(draft.file.name), color: AppColors.steel),
        title: Text(
          draft.file.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(formatFileSize(draft.file.size)),
        trailing: IconButton(
          tooltip: 'Quitar ${draft.file.name}',
          icon: const Icon(Icons.close_rounded),
          onPressed: onRemove,
        ),
      ),
    ),
  );
}

/// Resultado de la subida de adjuntos tras registrar el equipo: estado de cada archivo.
class AttachmentResults extends StatelessWidget {
  const AttachmentResults({super.key});

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<AttachmentsBloc, AttachmentsState>(
    builder: (context, state) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Equipo registrado',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          state.uploading
              ? 'Subiendo adjuntos…'
              : state.hasFailed
              ? 'No se pudieron subir ${state.failedCount} de ${state.drafts.length} adjuntos. El equipo ya está en el inventario.'
              : 'Adjuntos subidos.',
          key: const Key('results-summary'),
          style: const TextStyle(color: AppColors.slate, fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        for (final draft in state.drafts) _ResultTile(draft: draft),
      ],
    ),
  );
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.draft});

  final AttachmentDraft draft;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (draft.status) {
      AttachmentStatus.done => (
        Icons.check_circle_rounded,
        EquipmentColors.ok.dot,
      ),
      AttachmentStatus.failed => (Icons.error_rounded, AppColors.error),
      _ => (Icons.schedule_rounded, AppColors.slate),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.grey),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      draft.file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    formatFileSize(draft.file.size),
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              if (draft.status == AttachmentStatus.uploading) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: draft.progress == 0 ? null : draft.progress,
                ),
              ],
              if (draft.status == AttachmentStatus.failed &&
                  draft.failureMessage != null) ...[
                const SizedBox(height: 6),
                Text(
                  draft.failureMessage!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
