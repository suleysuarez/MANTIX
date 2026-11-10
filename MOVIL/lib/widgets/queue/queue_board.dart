import 'package:flutter/material.dart';

import '../../bloc/queue/request_board_bloc.dart';
import '../../core/format/queue_format.dart';
import '../../core/format/ticket_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/catalogs/catalog_models.dart';
import '../../models/requests/request_models.dart';
import '../shared/skeleton.dart';
import 'queue_card.dart';

/// Tablero horizontal de la bandeja: una columna por cada estado de la cola. La pantalla se
/// desplaza en vertical y el tablero en horizontal; cada columna carga y falla por separado.
class QueueBoard extends StatelessWidget {
  const QueueBoard({
    super.key,
    required this.columns,
    required this.now,
    required this.priorities,
    required this.categoryNames,
    required this.statusLabel,
    required this.onMore,
    required this.onRetry,
    this.onOpen,
    this.movingIds = const {},
  });

  final List<BoardColumn> columns;
  final DateTime now;
  final List<PriorityOption> priorities;
  final Map<String, String> categoryNames;

  /// Nombre general de un estado, por si el flujo trae uno que la app no rotula.
  final String Function(String status) statusLabel;
  final ValueChanged<String> onMore;
  final ValueChanged<String> onRetry;
  final ValueChanged<TicketListItem>? onOpen;
  final Set<int> movingIds;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width * 0.82).clamp(240.0, 320.0);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // Se alinea con el margen de la pantalla pero el desplazamiento llega al borde.
      clipBehavior: Clip.none,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final column in columns)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: SizedBox(
              width: width,
              child: QueueColumn(
                column: column,
                now: now,
                priorities: priorities,
                categoryNames: categoryNames,
                title: columnText(column.status, fallback: statusLabel(column.status)),
                onMore: () => onMore(column.status),
                onRetry: () => onRetry(column.status),
                onOpen: onOpen,
                movingIds: movingIds,
              ),
            ),
          ),
      ]),
    );
  }
}

/// Una columna: nombre, punto de color, contador y sus tarjetas con «Ver más».
class QueueColumn extends StatelessWidget {
  const QueueColumn({
    super.key,
    required this.column,
    required this.now,
    required this.priorities,
    required this.categoryNames,
    required this.title,
    required this.onMore,
    required this.onRetry,
    this.onOpen,
    this.movingIds = const {},
  });

  final BoardColumn column;
  final DateTime now;
  final List<PriorityOption> priorities;
  final Map<String, String> categoryNames;
  final ({String title, String hint}) title;
  final VoidCallback onMore;
  final VoidCallback onRetry;
  final ValueChanged<TicketListItem>? onOpen;
  final Set<int> movingIds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = statusMeta(column.status);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .22), borderRadius: AppRadius.lgAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: meta.colors.dot, shape: BoxShape.circle)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(title.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900))),
          const SizedBox(width: AppSpacing.sm),
          Semantics(
            label: '${column.total} solicitudes',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.pillAll),
              child: Text(column.phase == ColumnPhase.ready ? '${column.total}' : '–', style: theme.textTheme.labelMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900)),
            ),
          ),
        ]),
        if (title.hint.isNotEmpty) ...[
          const SizedBox(height: 2),
          Padding(padding: const EdgeInsets.only(left: 18), child: Text(title.hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel))),
        ],
        const SizedBox(height: AppSpacing.md),
        ..._body(context),
      ]),
    );
  }

  List<Widget> _body(BuildContext context) {
    final theme = Theme.of(context);
    switch (column.phase) {
      case ColumnPhase.loading:
        return [for (var i = 0; i < 2; i++) const Padding(padding: EdgeInsets.only(bottom: AppSpacing.sm), child: Skeleton(height: 110, radius: AppRadius.md))];
      case ColumnPhase.failure:
        return [
          Text(column.failure?.message ?? 'No pudimos cargar esta columna.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error)),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Reintentar')),
        ];
      case ColumnPhase.ready:
        return [
          if (column.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text('Sin solicitudes en esta columna.', textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel)),
            ),
          for (final ticket in column.items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: QueueCard(ticket: ticket, now: now, priorities: priorities, categoryNames: categoryNames, dimmed: movingIds.contains(ticket.id), onTap: onOpen == null ? null : () => onOpen!(ticket)),
            ),
          if (column.failure != null && column.items.isNotEmpty)
            Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: Text(column.failure!.message, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error))),
          if (column.loadingMore)
            const Padding(padding: EdgeInsets.all(AppSpacing.sm), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))))
          else if (column.hasMore)
            TextButton(
              onPressed: onMore,
              // El texto se encoge en columnas estrechas y con letra grande en vez de desbordar.
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.expand_more_rounded),
                const SizedBox(width: 6),
                Flexible(child: Text(column.failure != null ? 'Reintentar' : 'Ver más (${column.remaining} restantes)', maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ),
        ];
    }
  }
}
