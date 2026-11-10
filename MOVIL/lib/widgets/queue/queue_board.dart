import 'package:flutter/material.dart';

import '../../bloc/queue/request_board_bloc.dart';
import '../../core/format/queue_format.dart';
import '../../core/format/ticket_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/catalogs/catalog_models.dart';
import '../../models/queue/queue_workflow.dart';
import '../../models/requests/request_models.dart';
import '../shared/skeleton.dart';
import '../tickets/drag_auto_scroller.dart';
import 'queue_card.dart';

/// Tablero horizontal de la bandeja: una columna por cada estado de la cola. La pantalla se
/// desplaza en vertical y el tablero en horizontal; cada columna carga y falla por separado.
///
/// Una tarjeta se mueve con pulsación larga y arrastre (la pantalla y el tablero se desplazan
/// solos cerca del borde y solo se resaltan las columnas a las que se puede soltar) o con el
/// menú «Mover a…». Soltar en una columna no válida no mueve nada: [onMove] recibe el intento y
/// quien lo atiende explica por qué.
class QueueBoard extends StatefulWidget {
  const QueueBoard({
    super.key,
    required this.columns,
    required this.workflow,
    required this.now,
    required this.priorities,
    required this.categoryNames,
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
  final List<PriorityOption> priorities;
  final Map<String, String> categoryNames;

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
  final _horizontal = ScrollController();
  late final DragAutoScroller _sideScroller = DragAutoScroller(controller: _horizontal, edge: 56, step: 12);
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
    _sideScroller.stop();
    _pageScroller?.stop();
    _horizontal.dispose();
    super.dispose();
  }

  void _endDrag() {
    _sideScroller.stop();
    _pageScroller?.stop();
    if (_dragging != null && mounted) setState(() => _dragging = null);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final media = MediaQuery.of(context);
    _pageScroller?.update(details.globalPosition.dy, media.padding.top + kToolbarHeight, media.size.height - media.padding.bottom);
    _sideScroller.update(details.globalPosition.dx, 0, media.size.width);
  }

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width * 0.82).clamp(240.0, 320.0);
    return SingleChildScrollView(
      controller: _horizontal,
      scrollDirection: Axis.horizontal,
      // Se alinea con el margen de la pantalla pero el desplazamiento llega al borde.
      clipBehavior: Clip.none,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final column in widget.columns)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: SizedBox(
              width: width,
              child: QueueColumn(
                column: column,
                workflow: widget.workflow,
                now: widget.now,
                priorities: widget.priorities,
                categoryNames: widget.categoryNames,
                title: columnText(column.status, fallback: widget.statusLabel(column.status)),
                statusLabel: widget.statusLabel,
                onMore: () => widget.onMore(column.status),
                onRetry: () => widget.onRetry(column.status),
                onOpen: widget.onOpen,
                onMove: widget.onMove,
                movingIds: widget.movingIds,
                dragging: _dragging,
                onDragStarted: (ticket) => setState(() => _dragging = ticket),
                onDragUpdate: _onDragUpdate,
                onDragEnd: _endDrag,
              ),
            ),
          ),
      ]),
    );
  }
}

/// Una columna: nombre, punto de color, contador y sus tarjetas con «Ver más». Es también el
/// destino donde se sueltan las tarjetas.
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
  final List<PriorityOption> priorities;
  final Map<String, String> categoryNames;
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
    final meta = statusMeta(column.status);
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
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.skyLight.withValues(alpha: hovering ? .5 : .22),
              borderRadius: AppRadius.lgAll,
              border: Border.all(color: hovering ? AppColors.mustard : (valid ? meta.colors.dot : Colors.transparent), width: hovering ? 3 : 2),
            ),
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
      priorities: priorities,
      categoryNames: categoryNames,
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
        child: SizedBox(width: 250, child: QueueCard(ticket: ticket, now: now, priorities: priorities, categoryNames: categoryNames)),
      ),
      childWhenDragging: Opacity(opacity: .35, child: card),
      child: card,
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
              child: Text(_validTarget ? 'Suelta aquí' : 'Sin solicitudes en esta columna.', textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel)),
            ),
          for (final ticket in column.items) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: _card(ticket)),
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
