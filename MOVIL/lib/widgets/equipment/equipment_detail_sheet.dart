import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/equipment/equipment_detail_bloc.dart';
import '../../core/format/equipment_meta.dart';
import '../../core/format/formatters.dart';
import '../../core/format/ticket_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/equipment/equipment_models.dart';
import '../../models/requests/request_models.dart';
import '../../repositories/equipment/equipment_repository.dart';
import '../../repositories/requests/requests_repository.dart';
import '../shared/app_chip.dart';
import '../shared/detail_parts.dart';
import '../shared/error_state.dart';
import '../shared/mantix_sheet.dart';
import '../shared/skeleton.dart';
import '../shared/timeline.dart';

/// Ficha del equipo en una hoja inferior arrastrable: datos agrupados, historial (registro,
/// tickets y último mantenimiento) y adjuntos. [onOpenTicket] abre el detalle de un ticket.
Future<void> showEquipmentDetails(BuildContext context, Equipment item, {ValueChanged<int>? onOpenTicket}) => showMantixSheet<void>(
      context,
      title: 'Detalle del equipo',
      builder: (sheetContext, controller) => BlocProvider(
        create: (_) => EquipmentDetailBloc(
          equipmentId: item.id,
          equipment: context.read<EquipmentRepository>(),
          requests: context.read<RequestsRepository>(),
        )..add(const EquipmentDetailStarted()),
        child: EquipmentDetailBody(item: item, controller: controller, onOpenTicket: onOpenTicket),
      ),
    );

class EquipmentDetailBody extends StatelessWidget {
  const EquipmentDetailBody({super.key, required this.item, required this.controller, this.onOpenTicket});

  final Equipment item;
  final ScrollController controller;
  final ValueChanged<int>? onOpenTicket;

  @override
  Widget build(BuildContext context) {
    final last = item.lastMaintenanceAt;
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
      children: [
        DetailHeader(
          icon: equipmentCategoryIcon(item.typeCode),
          pill: item.assetTag,
          title: '${item.brand} ${item.model}',
          chips: [AppChip(label: equipmentStatusMeta(item.status).label, colors: equipmentStatusMeta(item.status).colors, semanticPrefix: 'Estado')],
        ),
        const SizedBox(height: AppSpacing.md),
        DetailSection(icon: Icons.info_outline_rounded, title: 'Información general', children: [
          DetailField('Código de activo', item.assetTag),
          DetailField('Categoría', item.typeName),
          DetailField('Número de serie', _orEmpty(item.serialNumber, 'Sin registrar')),
          if (item.description != null && item.description!.trim().isNotEmpty) DetailField('Descripción', item.description!),
        ]),
        const SizedBox(height: AppSpacing.md),
        DetailSection(icon: Icons.place_outlined, title: 'Ubicación y responsable', children: [
          DetailField('Ubicación', item.locationName ?? 'Sin ubicación'),
          DetailField('Responsable', item.custodianName ?? 'Sin responsable'),
        ]),
        const SizedBox(height: AppSpacing.md),
        DetailSection(icon: Icons.build_outlined, title: 'Mantenimiento', children: [
          DetailField('Último mantenimiento', last == null ? 'Sin mantenimientos' : formatDate(last.toLocal())),
        ]),
        const SizedBox(height: AppSpacing.md),
        DetailSection(icon: Icons.history_rounded, title: 'Historial', children: [_History(item: item, onOpenTicket: onOpenTicket)]),
        const SizedBox(height: AppSpacing.md),
        const DetailSection(icon: Icons.attach_file_rounded, title: 'Adjuntos', children: [_Attachments()]),
      ],
    );
  }
}

String _orEmpty(String? value, String fallback) => value == null || value.trim().isEmpty ? fallback : value;

class _History extends StatelessWidget {
  const _History({required this.item, required this.onOpenTicket});
  final Equipment item;
  final ValueChanged<int>? onOpenTicket;

  @override
  Widget build(BuildContext context) => BlocBuilder<EquipmentDetailBloc, EquipmentDetailState>(
        builder: (context, state) {
          final entries = <TimelineEntry>[
            if (item.createdAt != null) TimelineEntry(title: 'Equipo registrado', at: item.createdAt!, icon: Icons.add_circle_outline_rounded, color: AppColors.navy),
            if (item.lastMaintenanceAt != null) TimelineEntry(title: 'Último mantenimiento', at: item.lastMaintenanceAt!, icon: Icons.build_circle_outlined, color: const Color(0xFF065F46)),
            for (final ticket in state.tickets)
              TimelineEntry(
                title: 'Ticket ${ticket.ticketNumber} creado',
                subtitle: '${ticket.title} · ${statusMeta(ticket.status).label}',
                at: ticket.createdAt,
                icon: Icons.confirmation_number_outlined,
                color: statusMeta(ticket.status).colors.dot,
                onTap: onOpenTicket == null ? null : () => onOpenTicket!(ticket.id),
              ),
          ];
          final loading = state.ticketsStatus == DetailPart.loading;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (entries.isNotEmpty) Timeline(entries: entries),
            if (loading) const _InlineSkeleton(rows: 2),
            if (state.ticketsStatus == DetailPart.failure)
              ErrorState(failure: state.ticketsFailure!, onRetry: () => context.read<EquipmentDetailBloc>().add(const EquipmentDetailStarted())),
            if (!loading && state.ticketsStatus == DetailPart.success && state.tickets.isEmpty)
              Text('Este equipo aún no tiene tickets.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.slate)),
          ]);
        },
      );
}

class _Attachments extends StatelessWidget {
  const _Attachments();

  @override
  Widget build(BuildContext context) => BlocBuilder<EquipmentDetailBloc, EquipmentDetailState>(
        builder: (context, state) {
          switch (state.attachmentsStatus) {
            case DetailPart.loading:
              return const _InlineSkeleton(rows: 1);
            case DetailPart.failure:
              return ErrorState(failure: state.attachmentsFailure!, onRetry: () => context.read<EquipmentDetailBloc>().add(const EquipmentDetailStarted()));
            case DetailPart.success:
              if (state.attachments.isEmpty) {
                return Text('Sin adjuntos.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.slate));
              }
              return Column(children: [for (final attachment in state.attachments) _AttachmentRow(attachment)]);
          }
        },
      );
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow(this.attachment);
  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    final isImage = attachment.mimeType.startsWith('image/');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(children: [
        Icon(isImage ? Icons.image_outlined : Icons.description_outlined, color: AppColors.steel),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(attachment.fileName, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.navy))),
        const SizedBox(width: AppSpacing.sm),
        Text(formatFileSize(attachment.fileSize), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.slate)),
      ]),
    );
  }
}

/// Esqueleto en columna (no una lista): cabe dentro de la ficha, que ya se desplaza.
class _InlineSkeleton extends StatelessWidget {
  const _InlineSkeleton({required this.rows});
  final int rows;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < rows; i++) const Padding(padding: EdgeInsets.only(bottom: AppSpacing.sm), child: Skeleton(height: 40)),
      ]);
}
