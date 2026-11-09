import 'package:flutter/material.dart';

import '../../core/format/formatters.dart';
import '../../core/format/ticket_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/requests/request_models.dart';

String _time(DateTime date) {
  final local = date.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// Píldora de prioridad con icono y color propio.
class PriorityPill extends StatelessWidget {
  const PriorityPill(this.code, {super.key});
  final String code;

  @override
  Widget build(BuildContext context) {
    final meta = priorityMeta(code);
    return Semantics(
      label: 'Prioridad: ${meta.label}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: meta.colors.background, borderRadius: AppRadius.pillAll),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(priorityIcon(code), size: 13, color: meta.colors.foreground),
          const SizedBox(width: 4),
          Text(meta.label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: meta.colors.foreground, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

/// Fecha arriba y hora debajo, alineadas a la derecha.
class _DateStamp extends StatelessWidget {
  const _DateStamp(this.date);
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.slate);
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text(formatDate(date.toLocal()), style: style),
      Text(_time(date), style: style),
    ]);
  }
}

/// Tarjeta de la vista de tabla: icono de categoría, número, título, prioridad y fecha.
class TicketListCard extends StatelessWidget {
  const TicketListCard({super.key, required this.item, required this.onTap});
  final TicketListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = statusMeta(item.status);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll, side: BorderSide(color: AppColors.skyLight.withValues(alpha: .5))),
      child: InkWell(
        borderRadius: AppRadius.lgAll,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: status.colors.background, borderRadius: AppRadius.mdAll),
              child: Icon(categoryIcon(item.category), color: status.colors.foreground, size: 23),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.ticketNumber, style: theme.textTheme.labelMedium?.copyWith(color: AppColors.slate, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)),
                if (item.category != null) ...[
                  const SizedBox(height: 2),
                  Text(item.category!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate)),
                ],
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  PriorityPill(item.priority),
                  _StatusBadge(item.status),
                ]),
              ]),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Icon(Icons.chevron_right_rounded, color: AppColors.slate),
              const SizedBox(height: 24),
              _DateStamp(item.createdAt),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Estado en texto con punto de color (el color no es la única señal).
class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.code);
  final String code;

  @override
  Widget build(BuildContext context) {
    final meta = statusMeta(code);
    return Semantics(
      label: 'Estado: ${meta.label}',
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        DecoratedBox(decoration: BoxDecoration(color: meta.colors.dot, shape: BoxShape.circle), child: const SizedBox.square(dimension: 8)),
        const SizedBox(width: 5),
        Text(meta.label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: meta.colors.foreground, fontWeight: FontWeight.w700, decoration: meta.strikethrough ? TextDecoration.lineThrough : null)),
      ]),
    );
  }
}

/// Tarjeta compacta del Kanban: blanca sobre la columna de color.
class TicketKanbanCard extends StatelessWidget {
  const TicketKanbanCard({super.key, required this.item, required this.onTap});
  final TicketListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.white,
      borderRadius: AppRadius.mdAll,
      elevation: 0,
      child: InkWell(
        borderRadius: AppRadius.mdAll,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.ticketNumber, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.slate, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800, height: 1.2)),
            if (item.category != null)
              Text(item.category!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.slate)),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: Align(alignment: Alignment.centerLeft, child: PriorityPill(item.priority))),
              _DateStamp(item.createdAt),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// «Requieren atención prioritaria»: tickets críticos o altos aún abiertos, en un carrusel.
class TicketAttention extends StatefulWidget {
  const TicketAttention({super.key, required this.items, required this.onOpen});
  final List<TicketListItem> items;
  final ValueChanged<TicketListItem> onOpen;

  @override
  State<TicketAttention> createState() => _TicketAttentionState();
}

class _TicketAttentionState extends State<TicketAttention> {
  final _controller = PageController(viewportFraction: .92);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final urgent = widget.items
        .where((item) => (item.priority == 'critical' || item.priority == 'high') && !['resolved', 'closed', 'cancelled'].contains(item.status))
        .toList();
    if (urgent.isEmpty) return const SizedBox.shrink();
    final critical = urgent.where((item) => item.priority == 'critical').length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
        const SizedBox(width: 6),
        Expanded(child: Text('Requieren atención prioritaria', style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: StatusColors.critical.background, borderRadius: AppRadius.pillAll),
          child: Text(critical > 0 ? '$critical críticos' : '${urgent.length} altos', style: theme.textTheme.labelSmall?.copyWith(color: StatusColors.critical.foreground, fontWeight: FontWeight.w800)),
        ),
      ]),
      const SizedBox(height: 10),
      SizedBox(
        height: 128,
        child: PageView.builder(
          controller: _controller,
          padEnds: false,
          itemCount: urgent.length,
          onPageChanged: (page) => setState(() => _page = page),
          itemBuilder: (context, index) {
            final item = urgent[index];
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll, side: BorderSide(color: priorityMeta(item.priority).colors.dot.withValues(alpha: .35))),
                child: InkWell(
                  borderRadius: AppRadius.lgAll,
                  onTap: () => widget.onOpen(item),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(item.ticketNumber, style: theme.textTheme.labelMedium?.copyWith(color: AppColors.slate, fontWeight: FontWeight.w700))),
                        PriorityPill(item.priority),
                      ]),
                      const SizedBox(height: 4),
                      Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      Row(children: [
                        Expanded(child: _StatusBadge(item.status)),
                        Text('Ver', style: theme.textTheme.labelLarge?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w800)),
                        const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.steel),
                      ]),
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      if (urgent.length > 1) ...[
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < urgent.length && i < 8; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _page ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(color: i == _page ? AppColors.steel : AppColors.grey, borderRadius: AppRadius.pillAll),
            ),
        ]),
      ],
    ]);
  }
}
