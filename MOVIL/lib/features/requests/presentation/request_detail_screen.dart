import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/domain/ticket_meta.dart';
import '../../../core/format/formatters.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/app_chip.dart';
import '../../../shared/async_view.dart';
import '../../../models/requests/request_models.dart';
import '../data/requests_repository.dart';
import 'bloc/request_detail_bloc.dart';

/// Detalle de una solicitud: datos, estado, historial y adjuntos (solo lectura).
class RequestDetailScreen extends StatelessWidget {
  const RequestDetailScreen({super.key, required this.requestId});

  final int requestId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => RequestDetailBloc(repository: context.read<RequestsRepository>(), requestId: requestId)
        ..add(const RequestDetailRequested())
        ..add(const RequestAttachmentsRequested()),
      child: const _RequestDetailView(),
    );
  }
}

class _RequestDetailView extends StatelessWidget {
  const _RequestDetailView();

  /// Recarga el ticket y sus adjuntos; espera solo al ticket (los adjuntos cargan aparte).
  Future<void> _refresh(BuildContext context) {
    final bloc = context.read<RequestDetailBloc>();
    final done = Completer<void>();
    bloc
      ..add(RequestDetailRequested(done: done))
      ..add(const RequestAttachmentsRequested());
    return done.future;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RequestDetailBloc>().state;
    return Scaffold(
      appBar: AppBar(title: Text(state.ticket?.ticketNumber ?? 'Solicitud')),
      body: AsyncView<TicketDetail>(
        loaded: state.ticket,
        failure: state.failure,
        onRetry: () => _refresh(context),
        data: (ticket) => RefreshIndicator(
          onRefresh: () => _refresh(context),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(ticket.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [StatusChip(ticket.status), PriorityChip(ticket.priority)],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Field(label: 'Equipo', value: ticket.equipment.label),
              _Field(label: 'Técnico asignado', value: ticket.technicianName ?? 'Sin asignar'),
              _Field(label: 'Creada', value: formatDateTime(ticket.createdAt)),
              _Field(label: 'Última actualización', value: formatDateTime(ticket.updatedAt)),
              _Field(label: 'Descripción', value: ticket.description),
              if (ticket.resolutionSummary != null) _Field(label: 'Resolución', value: ticket.resolutionSummary!),
              const SizedBox(height: AppSpacing.md),
              Text('Historial', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              for (final entry in ticket.history) _HistoryTile(entry: entry),
              const SizedBox(height: AppSpacing.lg),
              Text('Adjuntos', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              const _Attachments(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final StatusHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final from = entry.fromStatus == null ? null : statusMeta(entry.fromStatus!).label;
    final to = statusMeta(entry.toStatus).label;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(from == null ? to : '$from → $to', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
          Text(formatDateTime(entry.changedAt), style: theme.textTheme.bodySmall),
          if (entry.notes != null) Text(entry.notes!, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Los adjuntos cargan aparte: si fallan, el resto del detalle sigue visible.
class _Attachments extends StatelessWidget {
  const _Attachments();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RequestDetailBloc>().state;
    return switch (state.attachmentsStatus) {
      LoadStatus.loading => const LinearProgressIndicator(semanticsLabel: 'Cargando adjuntos'),
      LoadStatus.failure => Row(
          children: [
            const Expanded(child: Text('No pudimos cargar los adjuntos.')),
            TextButton(
              onPressed: () => context.read<RequestDetailBloc>().add(const RequestAttachmentsRequested()),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      LoadStatus.success => state.attachments.isEmpty
          ? const Text('Esta solicitud no tiene adjuntos.')
          : Column(
              children: [
                for (final item in state.attachments)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(item.mimeType.startsWith('image/') ? Icons.image_outlined : Icons.attach_file),
                    title: Text(item.fileName),
                    subtitle: Text(formatFileSize(item.fileSize)),
                  ),
              ],
            ),
    };
  }
}
