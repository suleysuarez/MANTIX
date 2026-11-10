import 'package:flutter/material.dart';

import '../../bloc/queue/request_board_bloc.dart';
import '../../core/format/queue_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/queue/queue_workflow.dart';
import '../../models/requests/request_models.dart';
import '../shared/skeleton.dart';
import '../tickets/drag_auto_scroller.dart';
import 'queue_card.dart';

/// Tablero de la bandeja: una columna por cada estado de la cola, todas del mismo tamaño y
/// repartidas en todo el ancho de la pantalla, sin desplazamiento horizontal. La pantalla se
/// desplaza en vertical; cada columna carga y falla por separado.
///
/// Una tarjeta se mueve con pulsación larga y arrastre (la pantalla se desplaza sola cerca del
/// borde de arriba o de abajo y solo se resaltan las columnas a las que se puede soltar) o con el
/// menú «Mover a…». Soltar en una columna no válida no mueve nada: [onMove] recibe el intento y
/// quien lo atiende explica por qué.
class QueueBoard extends StatefulWidget {
  const QueueBoard({
    super.key,
    required this.columns,
    required this.workflow,
    required this.now,
    required this.statusLabel,
    required this.onMore,
    required this.onRetry,
    this.onOpen,
    this.onMove,
    this.movingIds = const {},
    this.pageController,
  });

  final List<BoardColumn> columns;
  final QueueWorkflow workflow;
  final DateTime now;

  /// Nombre general de un estado, por si el flujo trae uno que la app no rotula.
  final String Function(String status) statusLabel;
  final ValueChanged<String> onMore;
  final ValueChanged<String> onRetry;
  final ValueChanged<TicketListItem>? onOpen;
  final void Function(TicketListItem ticket, String target)? onMove;
  final Set<int> movingIds;

  /// Controlador de la pantalla que contiene al tablero: se desplaza solo al arrastrar cerca
  /// del borde de arriba o de abajo.
  final ScrollController? pageController;

  @override
  State<QueueBoard> createState() => _QueueBoardState();
}

class _QueueBoardState extends State<QueueBoard> {
  DragAutoScroller? _pageScroller;
  TicketListItem? _dragging;

  @override
  void initState() {
    super.initState();
    _pageScroller = _newPageScroller();
  }

  DragAutoScroller? _newPageScroller() => widget.pageController == null ? null : DragAutoScroller(controller: widget.pageController!);

  @override
  void didUpdateWidget(QueueBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageController != widget.pageController) {
      _pageScroller?.stop();
      _pageScroller = _newPageScroller();
    }
  }

  @override
  void dispose() {
    _pageScroller?.stop();
    super.dispose();
  }

  void _endDrag() {
    _pageScroller?.stop();
    if (_dragging != null && mounted) setState(() => _dragging = null);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final media = MediaQuery.of(context);
    _pageScroller?.update(details.globalPosition.dy, media.padding.top + kToolbarHeight, media.size.height - media.padding.bottom);
  }

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < widget.columns.length; i++) ...[
          if (i > 0) const SizedBox(width: _gap),
          // Todas las columnas miden lo mismo, tenga cada una pocas o muchas tarjetas.
          Expanded(
            child: QueueColumn(
              column: widget.columns[i],
              workflow: widget.workflow,
              now: widget.now,
              title: columnText(widget.columns[i].status, fallback: widget.statusLabel(widget.columns[i].status)),
              statusLabel: widget.statusLabel,
              onMore: () => widget.onMore(widget.columns[i].status),
              onRetry: () => widget.onRetry(widget.columns[i].status),
              onOpen: widget.onOpen,
              onMove: widget.onMove,
              movingIds: widget.movingIds,
              dragging: _dragging,
              onDragStarted: (ticket) => setState(() => _dragging = ticket),
              onDragUpdate: _onDragUpdate,
              onDragEnd: _endDrag,
            ),
          ),
        ],
      ]);

  static const _gap = 6.0;
}

/// Una columna: nombre, punto de color, contador y sus tarjetas con «Ver más». Es también el
/// destino donde se sueltan las tarjetas.
class QueueColumn extends StatelessWidget {
  const QueueColumn({
    super.key,
    required this.column,
    required this.now,
    required this.title,
    required this.onMore,
    required this.onRetry,
    this.workflow = const QueueWorkflow(),
    this.statusLabel = _identity,
    this.onOpen,
    this.onMove,
    this.movingIds = const {},
    this.dragging,
    this.onDragStarted,
    this.onDragUpdate,
    this.onDragEnd,
  });

  static String _identity(String status) => status;

  final BoardColumn column;
  final QueueWorkflow workflow;
  final DateTime now;
  final ({String title, String hint}) title;
  final String Function(String status) statusLabel;
  final VoidCallback onMore;
  final VoidCallback onRetry;
  final ValueChanged<TicketListItem>? onOpen;
  final void Function(TicketListItem ticket, String target)? onMove;
  final Set<int> movingIds;

  /// La tarjeta que se está arrastrando, si hay una.
  final TicketListItem? dragging;
  final ValueChanged<TicketListItem>? onDragStarted;
  final ValueChanged<DragUpdateDetails>? onDragUpdate;
  final VoidCallback? onDragEnd;

  /// ¿Se puede soltar aquí la tarjeta que se arrastra?
  bool get _validTarget => dragging != null && workflow.canMove(dragging!, column.status);

  List<({String status, String label})> _targets(TicketListItem ticket) => [
        for (final status in workflow.targetsFor(ticket)) (status: status, label: moveLabel(status, fallback: statusLabel(status))),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valid = _validTarget;
    return DragTarget<TicketListItem>(
      // Se acepta todo: soltar donde no se puede devuelve la tarjeta y se explica por qué.
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        final ticket = details.data;
        if (ticket.status != column.status) onMove?.call(ticket, column.status);
      },
      builder: (context, candidates, rejected) {
        final hovering = candidates.isNotEmpty && valid;
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: dragging != null && !valid && dragging!.status != column.status ? .55 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(4),
            // Sin color propio por estado: solo se tiñe de mostaza al soltar una tarjeta encima.
            decoration: BoxDecoration(
              color: hovering ? AppColors.mustard.withValues(alpha: .28) : AppColors.skyLight.withValues(alpha: .18),
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: hovering ? AppColors.mustard : (valid ? AppColors.steel : AppColors.skyLight.withValues(alpha: .6)), width: hovering ? 3 : (valid ? 2 : 1)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Semantics(
                container: true,
                label: '${title.title}${title.hint.isEmpty ? '' : ', ${title.hint}'}, ${column.total} solicitudes',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(3, 4, 3, 0),
                  // El nombre y cuántas hay van en la misma línea; en una columna estrecha se encogen juntos.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(title.title, maxLines: 1, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.pillAll, border: Border.all(color: AppColors.skyLight)),
                        child: Text(column.phase == ColumnPhase.ready ? '${column.total}' : '–', style: theme.textTheme.labelMedium?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w900)),
                      ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ..._body(context),
            ]),
          ),
        );
      },
    );
  }

  Widget _card(TicketListItem ticket) {
    final moving = movingIds.contains(ticket.id);
    final card = QueueCard(
      ticket: ticket,
      now: now,
      dimmed: moving,
      onTap: onOpen == null ? null : () => onOpen!(ticket),
      moveTargets: moving ? const [] : _targets(ticket),
      onMove: onMove == null ? null : (target) => onMove!(ticket, target),
    );
    // Solo se arrastra lo que se puede mover: sin permiso sobre la solicitud no hay arrastre.
    if (moving || !ticket.canAct || onMove == null) return card;
    return LongPressDraggable<TicketListItem>(
      data: ticket,
      onDragStarted: () => onDragStarted?.call(ticket),
      onDragUpdate: onDragUpdate,
      onDragEnd: (_) => onDragEnd?.call(),
      onDraggableCanceled: (_, _) => onDragEnd?.call(),
      feedback: Material(
        color: Colors.transparent,
        elevation: 8,
        borderRadius: AppRadius.mdAll,
        child: SizedBox(width: 150, child: QueueCard(ticket: ticket, now: now)),
      ),
      childWhenDragging: Opacity(opacity: .35, child: card),
      child: card,
    );
  }

  List<Widget> _body(BuildContext context) {
    final theme = Theme.of(context);
    switch (column.phase) {
      case ColumnPhase.loading:
        return [for (var i = 0; i < 2; i++) const Padding(padding: EdgeInsets.only(bottom: 6), child: Skeleton(height: 120, radius: AppRadius.md))];
      case ColumnPhase.failure:
        return [
          Text(column.failure?.message ?? 'No pudimos cargar esta columna.', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.error)),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(onPressed: onRetry, style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)), child: const Text('Reintentar', maxLines: 1)),
        ];
      case ColumnPhase.ready:
        return [
          if (column.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(_validTarget ? 'Suelta aquí' : 'Sin solicitudes', textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel)),
            ),
          for (final ticket in column.items) Padding(padding: const EdgeInsets.only(bottom: 6), child: _card(ticket)),
          if (column.failure != null && column.items.isNotEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(column.failure!.message, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.error))),
          if (column.loadingMore)
            const Padding(padding: EdgeInsets.all(AppSpacing.sm), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))))
          else if (column.hasMore)
            TextButton(
              onPressed: onMore,
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6), foregroundColor: AppColors.steel),
              // Corto y a dos líneas si hace falta: la columna mide un tercio de la pantalla.
              child: Text(column.failure != null ? 'Reintentar' : 'Ver ${column.remaining} más', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
        ];
    }
  }
}
