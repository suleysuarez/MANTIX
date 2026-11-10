import 'package:flutter/material.dart';

import '../../core/format/ticket_meta.dart';
import '../../models/requests/request_models.dart';
import 'ticket_move_sheets.dart';

/// Datos que el usuario dio para mover un ticket. Según el estado de destino: texto
/// ([notes], [resolutionSummary]), clasificación ([category] y [priority]) o un técnico.
class TicketMoveInput {
  const TicketMoveInput({this.notes, this.resolutionSummary, this.category, this.priority, this.technicianId, this.technicianName});

  final String? notes;
  final String? resolutionSummary;
  final String? category;
  final String? priority;
  final int? technicianId;
  final String? technicianName;
}

/// Datos que el tablero sabe pedir en un diálogo corto.
const _askableText = {'resolution_summary', 'reason'};

/// Pide lo que el estado de destino exige antes de mover [ticket] a [target]:
///
/// * categoría y prioridad (`category`, `priority`): hoja de clasificación;
/// * técnico (`technician`): hoja para elegir un técnico activo;
/// * resolución o motivo: diálogo corto de texto;
/// * nada: no pregunta.
///
/// Devuelve lo dado (vacío si no hace falta nada) o `null` si se cancela.
Future<TicketMoveInput?> askTicketMoveData(
  BuildContext context, {
  required TicketListItem ticket,
  required String target,
  required List<String> requires,
}) async {
  if (requires.contains('category') || requires.contains('priority')) return showClassifySheet(context, ticket: ticket);
  if (requires.contains('technician')) return showAssignSheet(context, ticket: ticket);
  if (requires.isEmpty) return const TicketMoveInput();

  final label = statusMeta(target).label;
  if (requires.any((item) => !_askableText.contains(item))) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pasar a «$label»'),
        content: const Text('Este cambio necesita datos que la app todavía no sabe pedir. Hazlo desde la web.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
      ),
    );
    return null;
  }

  final isResolution = requires.contains('resolution_summary');
  return showDialog<TicketMoveInput>(
    context: context,
    builder: (context) => _TextRequestDialog(
      title: 'Pasar a «$label»',
      fieldLabel: isResolution ? 'Resumen de la solución' : 'Motivo',
      hint: isResolution ? 'Qué se hizo para resolverlo' : 'Por qué se cancela',
      confirm: 'Mover',
      ticketNumber: ticket.ticketNumber,
      onConfirm: (text) => isResolution ? TicketMoveInput(resolutionSummary: text) : TicketMoveInput(notes: text),
    ),
  );
}

class _TextRequestDialog extends StatefulWidget {
  const _TextRequestDialog({required this.title, required this.fieldLabel, required this.hint, required this.confirm, required this.ticketNumber, required this.onConfirm});

  final String title;
  final String fieldLabel;
  final String hint;
  final String confirm;
  final String ticketNumber;
  final TicketMoveInput Function(String text) onConfirm;

  @override
  State<_TextRequestDialog> createState() => _TextRequestDialogState();
}

class _TextRequestDialogState extends State<_TextRequestDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) {
      setState(() => _error = '${widget.fieldLabel} es obligatorio.');
      return;
    }
    Navigator.pop(context, widget.onConfirm(text));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.ticketNumber, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 3,
              maxLength: 500,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(labelText: widget.fieldLabel, hintText: widget.hint, errorText: _error),
              onChanged: (_) => setState(() => _error = null),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: _submit, child: Text(widget.confirm)),
        ],
      );
}
