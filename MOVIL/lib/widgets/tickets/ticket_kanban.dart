import 'package:flutter/material.dart';

import '../../core/format/ticket_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/requests/request_models.dart';
import 'ticket_cards.dart';

/// Transiciones que el backend permite desde cada estado (arrastrar y soltar).
const ticketTransitions = <String, Set<String>>{
  'submitted': {},
  'triaged': {},
  'assigned': {'in_progress'},
  'in_progress': {'waiting'},
  'waiting': {'in_progress'},
  'resolved': {'closed', 'in_progress'},
  'closed': {},
  'cancelled': {},
};

const _lanesPerPage = 2;

/// Número de páginas del Kanban para [lanes] columnas (dos por página).
int kanbanPageCount(int lanes) => (lanes / _lanesPerPage).ceil();

/// Kanban vertical: columnas de color, de dos en dos, que se deslizan hacia los lados.
/// Cada columna se desplaza hacia abajo; mantener pulsada una tarjeta permite soltarla en
/// otra columna visible (solo si la transición existe y el usuario puede actuar).
class TicketKanban extends StatelessWidget {
  const TicketKanban({
    super.key,
    required this.controller,
    required this.items,
    required this.lanes,
    required this.onOpen,
    required this.onMove,
    required this.onPageChanged,
  });

  final PageController controller;
  final List<TicketListItem> items;
  final List<String> lanes;
  final ValueChanged<TicketListItem> onOpen;
  final Future<void> Function(TicketListItem, String) onMove;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 560,
        child: PageView.builder(
          controller: controller,
          itemCount: kanbanPageCount(lanes.length),
          onPageChanged: onPageChanged,
          itemBuilder: (context, page) {
            final pageLanes = lanes.skip(page * _lanesPerPage).take(_lanesPerPage).toList();
            return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < _lanesPerPage; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: i < pageLanes.length
                      ? _Lane(lane: pageLanes[i], items: items.where((item) => item.status == pageLanes[i]).toList(), onOpen: onOpen, onMove: onMove)
                      : const SizedBox.shrink(),
                ),
              ],
            ]);
          },
        ),
      );
}

class _Lane extends StatelessWidget {
  const _Lane({required this.lane, required this.items, required this.onOpen, required this.onMove});

  final String lane;
  final List<TicketListItem> items;
  final ValueChanged<TicketListItem> onOpen;
  final Future<void> Function(TicketListItem, String) onMove;

  @override
  Widget build(BuildContext context) {
    final meta = statusMeta(lane);
    final theme = Theme.of(context);
    return DragTarget<TicketListItem>(
      onWillAcceptWithDetails: (details) => details.data.status != lane && (ticketTransitions[details.data.status]?.contains(lane) ?? false) && details.data.canAct,
      onAcceptWithDetails: (details) => onMove(details.data, lane),
      builder: (context, candidates, rejected) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: meta.colors.background.withValues(alpha: candidates.isEmpty ? .55 : 1),
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: meta.colors.dot.withValues(alpha: candidates.isEmpty ? .18 : .8), width: candidates.isEmpty ? 1 : 2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
              child: Icon(statusIcon(lane), size: 16, color: meta.colors.foreground),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(meta.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge?.copyWith(color: meta.colors.foreground, fontWeight: FontWeight.w800))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: Colors.white, borderRadius: AppRadius.pillAll),
              child: Text('${items.length}', style: theme.textTheme.labelMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: items.isEmpty
                ? Center(child: Text('Sin tickets', style: theme.textTheme.bodySmall?.copyWith(color: meta.colors.foreground.withValues(alpha: .7))))
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final card = TicketKanbanCard(item: item, onTap: () => onOpen(item));
                      if (!item.canAct) return card;
                      return LongPressDraggable<TicketListItem>(
                        data: item,
                        feedback: Material(
                          color: Colors.transparent,
                          elevation: 6,
                          child: SizedBox(width: 160, child: TicketKanbanCard(item: item, onTap: () {})),
                        ),
                        childWhenDragging: Opacity(opacity: .35, child: card),
                        child: card,
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
