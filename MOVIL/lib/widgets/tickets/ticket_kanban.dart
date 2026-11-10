import 'package:flutter/material.dart';

import '../../bloc/tickets/ticket_board_bloc.dart';
import '../../core/format/ticket_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/requests/request_models.dart';
import 'drag_auto_scroller.dart';
import 'ticket_cards.dart';

/// Estados que se dibujan mientras el servidor no ha enviado el flujo.
const defaultKanbanLanes = <String>['submitted', 'triaged', 'assigned', 'in_progress', 'waiting', 'resolved', 'closed', 'cancelled'];

/// Tablero por estados: secciones de color, una debajo de otra (sin desplazamiento
/// horizontal), cada una con su contador y colapsable. Se pueden mover tarjetas de dos formas:
/// arrastrando con pulsación larga (la pantalla se desplaza sola cerca del borde y solo se
/// resaltan los destinos válidos) o con el menú «Mover a…» de cada tarjeta.
class TicketKanban extends StatefulWidget {
  const TicketKanban({
    super.key,
    required this.items,
    required this.board,
    required this.onOpen,
    required this.onMove,
    this.scrollController,
    this.highlightId,
  });

  final List<TicketListItem> items;
  final TicketBoardState board;
  final ValueChanged<TicketListItem> onOpen;

  /// Se llama al soltar (o elegir en el menú) con el ticket y el estado de destino ya
  /// comprobado como válido.
  final void Function(TicketListItem ticket, String target) onMove;

  /// Controlador de la lista que contiene el tablero, para desplazarla al arrastrar.
  final ScrollController? scrollController;
  final int? highlightId;

  @override
  State<TicketKanban> createState() => _TicketKanbanState();
}

class _TicketKanbanState extends State<TicketKanban> {
  /// Secciones que el usuario abrió o cerró a mano; el resto se abre si tiene tickets.
  final _manual = <String, bool>{};
  TicketListItem? _dragging;
  late DragAutoScroller? _scroller = _newScroller();

  DragAutoScroller? _newScroller() => widget.scrollController == null ? null : DragAutoScroller(controller: widget.scrollController!);

  @override
  void didUpdateWidget(TicketKanban oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      _scroller?.stop();
      _scroller = _newScroller();
    }
  }

  @override
  void dispose() {
    _scroller?.stop();
    super.dispose();
  }

  List<String> get _lanes => widget.board.workflow.isEmpty ? defaultKanbanLanes : [for (final state in widget.board.workflow) state.status];

  void _endDrag() {
    _scroller?.stop();
    if (_dragging != null && mounted) setState(() => _dragging = null);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final media = MediaQuery.of(context);
    _scroller?.update(details.globalPosition.dy, media.padding.top + kToolbarHeight, media.size.height - media.padding.bottom);
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        for (final lane in _lanes)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _Section(
              lane: lane,
              items: widget.items.where((item) => item.status == lane).toList(),
              board: widget.board,
              expanded: _manual[lane] ?? widget.items.any((item) => item.status == lane),
              dragging: _dragging,
              highlightId: widget.highlightId,
              onToggle: (expanded) => setState(() => _manual[lane] = expanded),
              onOpen: widget.onOpen,
              onMove: widget.onMove,
              onDragStarted: (item) => setState(() => _dragging = item),
              onDragUpdate: _onDragUpdate,
              onDragEnd: _endDrag,
            ),
          ),
      ]);
}

class _Section extends StatelessWidget {
  const _Section({
    required this.lane,
    required this.items,
    required this.board,
    required this.expanded,
    required this.dragging,
    required this.highlightId,
    required this.onToggle,
    required this.onOpen,
    required this.onMove,
    required this.onDragStarted,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final String lane;
  final List<TicketListItem> items;
  final TicketBoardState board;
  final bool expanded;
  final TicketListItem? dragging;
  final int? highlightId;
  final ValueChanged<bool> onToggle;
  final ValueChanged<TicketListItem> onOpen;
  final void Function(TicketListItem, String) onMove;
  final ValueChanged<TicketListItem> onDragStarted;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final meta = statusMeta(lane);
    final theme = Theme.of(context);
    final validTarget = dragging != null && board.canMove(dragging!, lane);
    return DragTarget<TicketListItem>(
      onWillAcceptWithDetails: (details) => board.canMove(details.data, lane),
      onAcceptWithDetails: (details) => onMove(details.data, lane),
      builder: (context, candidates, rejected) {
        final hovering = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: meta.colors.background.withValues(alpha: hovering ? 1 : .55),
            borderRadius: AppRadius.lgAll,
            border: Border.all(
              color: hovering ? AppColors.mustard : (validTarget ? meta.colors.dot : meta.colors.dot.withValues(alpha: .18)),
              width: hovering ? 3 : (validTarget ? 2 : 1),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(
              button: true,
              label: '${meta.label}, ${items.length} ${items.length == 1 ? 'ticket' : 'tickets'}, ${expanded ? 'abierto' : 'cerrado'}',
              excludeSemantics: true,
              child: InkWell(
                borderRadius: AppRadius.lgAll,
                onTap: () => onToggle(!expanded),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: AppRadius.smAll),
                        child: Icon(statusIcon(lane), size: 18, color: meta.colors.foreground),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(meta.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: meta.colors.foreground, fontWeight: FontWeight.w800))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: AppRadius.pillAll),
                        child: Text('${items.length}', style: theme.textTheme.labelLarge?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 4),
                      Icon(expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: meta.colors.foreground),
                    ]),
                  ),
                ),
              ),
            ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: Text(validTarget ? 'Suelta aquí' : 'Sin tickets', style: theme.textTheme.bodySmall?.copyWith(color: meta.colors.foreground.withValues(alpha: .8)))),
                      )
                    : Column(children: [
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0) const SizedBox(height: 8),
                          _DraggableCard(
                            item: items[i],
                            board: board,
                            highlighted: items[i].id == highlightId,
                            onOpen: onOpen,
                            onMove: onMove,
                            onDragStarted: onDragStarted,
                            onDragUpdate: onDragUpdate,
                            onDragEnd: onDragEnd,
                          ),
                        ],
                      ]),
              ),
          ]),
        );
      },
    );
  }
}

class _DraggableCard extends StatelessWidget {
  const _DraggableCard({
    required this.item,
    required this.board,
    required this.highlighted,
    required this.onOpen,
    required this.onMove,
    required this.onDragStarted,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final TicketListItem item;
  final TicketBoardState board;
  final bool highlighted;
  final ValueChanged<TicketListItem> onOpen;
  final void Function(TicketListItem, String) onMove;
  final ValueChanged<TicketListItem> onDragStarted;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final targets = board.targetsFor(item);
    final moving = board.movingIds.contains(item.id);
    final card = TicketKanbanCard(
      item: item,
      highlighted: highlighted,
      moving: moving,
      targets: targets,
      onTap: () => onOpen(item),
      onMove: (target) => onMove(item, target),
    );
    if (targets.isEmpty) return card;
    return LongPressDraggable<TicketListItem>(
      data: item,
      onDragStarted: () => onDragStarted(item),
      onDragUpdate: onDragUpdate,
      onDragEnd: (_) => onDragEnd(),
      onDraggableCanceled: (_, _) => onDragEnd(),
      feedback: Material(
        color: Colors.transparent,
        elevation: 8,
        child: SizedBox(width: 260, child: TicketKanbanCard(item: item, onTap: () {})),
      ),
      childWhenDragging: Opacity(opacity: .35, child: card),
      child: card,
    );
  }
}
