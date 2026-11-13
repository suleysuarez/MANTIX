import 'package:flutter/material.dart';

import '../../core/format/ticket_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/requests/request_models.dart';
import '../shared/detail_parts.dart';

/// Lo que el técnico trabaja: iniciar, poner en espera y resolver. El resto de estados (cerrar,
/// cancelar, asignar, clasificar) son de quien supervisa y se hacen desde el tablero.
const technicianTargets = ['in_progress', 'waiting', 'resolved'];

/// Máximos del servidor para el texto de la resolución y de la nota.
const resolutionMaxLength = 1000;
const noteMaxLength = 500;

/// Los estados a los que se ofrece pasar [ticket] ahora: los que el flujo permite desde su estado,
/// que la cuenta puede usar (`canEnter`) y que la app sabe pedir (solo piden la resolución o nada).
/// Siguen el orden de [technicianTargets].
List<String> availableTargets(TicketDetail ticket, List<WorkflowStatus> workflow) {
  final byStatus = {for (final item in workflow) item.status: item};
  final allowed = byStatus[ticket.status]?.allowedTargets ?? const <String>[];
  return [
    for (final target in technicianTargets)
      if (allowed.contains(target) && (byStatus[target]?.canEnter ?? false) && (byStatus[target]?.requires ?? const <String>[]).every((item) => item == 'resolution_summary')) target,
  ];
}

/// Nombre del botón según de dónde viene el ticket y a dónde va.
String actionLabel(String from, String target) => switch (target) {
      'in_progress' => switch (from) { 'waiting' => 'Reanudar trabajo', 'resolved' => 'Reabrir ticket', _ => 'Iniciar trabajo' },
      'waiting' => 'Poner en espera',
      'resolved' => 'Resolver ticket',
      _ => statusMeta(target).label,
    };

IconData actionIcon(String target) => switch (target) {
      'in_progress' => Icons.play_arrow_rounded,
      'waiting' => Icons.pause_circle_outline_rounded,
      'resolved' => Icons.check_circle_outline_rounded,
      _ => Icons.swap_horiz_rounded,
    };

/// Las acciones del técnico sobre el ticket abierto. «Resolver ticket» es el botón principal
/// (mostaza) y pide escribir cómo se resolvió; los demás piden una nota opcional. No pinta nada si
/// no hay a dónde pasar.
class TicketActions extends StatelessWidget {
  const TicketActions({super.key, required this.ticket, required this.workflow, required this.changing, required this.onChange});

  final TicketDetail ticket;
  final List<WorkflowStatus> workflow;

  /// Hay un cambio en curso: los botones se deshabilitan.
  final bool changing;

  /// Se confirmó el cambio a [target] con el texto dado (resolución o nota).
  final void Function(String target, {String? notes, String? resolutionSummary}) onChange;

  Future<void> _ask(BuildContext context, String target) async {
    final needsResolution = (workflow.where((item) => item.status == target).firstOrNull?.requires ?? const <String>[]).contains('resolution_summary');
    final text = await showDialog<String>(
      context: context,
      builder: (context) => _ChangeDialog(ticketNumber: ticket.ticketNumber, title: actionLabel(ticket.status, target), needsResolution: needsResolution),
    );
    if (text == null) return;
    if (needsResolution) {
      onChange(target, resolutionSummary: text);
    } else {
      onChange(target, notes: text.isEmpty ? null : text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final targets = availableTargets(ticket, workflow);
    if (targets.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: DetailSection(icon: Icons.bolt_rounded, title: 'Acciones', children: [
        Text('Estado actual: ${statusMeta(ticket.status).label}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.steel)),
        const SizedBox(height: AppSpacing.sm),
        for (final target in targets)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: target == 'resolved'
                ? FilledButton.icon(
                    onPressed: changing ? null : () => _ask(context, target),
                    icon: _icon(target),
                    label: Text(actionLabel(ticket.status, target)),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.mustard, foregroundColor: AppColors.navy, disabledBackgroundColor: AppColors.grey, minimumSize: const Size.fromHeight(50), textStyle: const TextStyle(fontWeight: FontWeight.w800)),
                  )
                : OutlinedButton.icon(
                    onPressed: changing ? null : () => _ask(context, target),
                    icon: _icon(target),
                    label: Text(actionLabel(ticket.status, target)),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.navy, side: const BorderSide(color: AppColors.mustard, width: 1.5), minimumSize: const Size.fromHeight(50), textStyle: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
          ),
        if (changing) const Padding(padding: EdgeInsets.only(top: AppSpacing.md), child: LinearProgressIndicator(minHeight: 3, color: AppColors.mustard, backgroundColor: AppColors.skyLight)),
      ]),
    );
  }

  Widget _icon(String target) => changing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(actionIcon(target));
}

/// Pide el texto del cambio: la resolución (obligatoria) o una nota (opcional). Devuelve el texto
/// sin espacios sobrantes, o `null` si se cancela.
class _ChangeDialog extends StatefulWidget {
  const _ChangeDialog({required this.ticketNumber, required this.title, required this.needsResolution});

  final String ticketNumber;
  final String title;
  final bool needsResolution;

  @override
  State<_ChangeDialog> createState() => _ChangeDialogState();
}

class _ChangeDialogState extends State<_ChangeDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final text = _controller.text.trim();
    if (widget.needsResolution && text.isEmpty) {
      setState(() => _error = 'Escribe cómo se resolvió el ticket.');
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.ticketNumber, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: widget.needsResolution ? 3 : 2,
              maxLines: 6,
              maxLength: widget.needsResolution ? resolutionMaxLength : noteMaxLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: widget.needsResolution ? 'Cómo se resolvió' : 'Nota (opcional)',
                hintText: widget.needsResolution ? 'Describe qué hiciste para resolverlo' : 'Algo que quieras dejar anotado',
                errorText: _error,
              ),
              onChanged: (_) => _error == null ? null : setState(() => _error = null),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: _confirm, style: FilledButton.styleFrom(backgroundColor: AppColors.mustard, foregroundColor: AppColors.navy), child: Text(widget.needsResolution ? 'Resolver' : 'Confirmar')),
        ],
      );
}
