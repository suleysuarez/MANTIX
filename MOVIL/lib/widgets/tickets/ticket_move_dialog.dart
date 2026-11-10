import 'package:flutter/material.dart';

import '../../core/format/ticket_meta.dart';
import '../../models/requests/request_models.dart';

/// Datos que el usuario escribió para mover un ticket.
class TicketMoveInput {
  const TicketMoveInput({this.notes, this.resolutionSummary});

  final String? notes;
  final String? resolutionSummary;
}

/// Datos que el tablero sabe pedir. El resto (categoría, prioridad, técnico) necesita sus
/// propios catálogos y se hace desde el detalle del ticket.
const _askable = {'resolution_summary', 'reason'};

/// Pide lo que el estado de destino exige antes de mover [ticket] a [target]. Devuelve lo
/// escrito (vacío si no hace falta nada) o `null` si se cancela o el cambio no se puede hacer
/// desde el tablero; en ese caso [onOpenDetail] abre el ticket para hacerlo allí.
Future<TicketMoveInput?> askTicketMoveData(
  BuildContext context, {
  required TicketListItem ticket,
  required String target,
  required List<String> requires,
  required VoidCallback onOpenDetail,
}) async {
  final label = statusMeta(target).label;
  final unsupported = requires.where((item) => !_askable.contains(item)).toList();
  if (unsupported.isNotEmpty) {
    final names = {'category': 'la categoría', 'priority': 'la prioridad', 'technician': 'el técnico'};
    final needs = [for (final item in unsupported) names[item] ?? item].join(' y ');
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pasar a «$label»'),
        content: Text('Para este cambio hay que indicar $needs. Ábrelo para completarlo desde el detalle del ticket.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Entendido')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Abrir ticket')),
        ],
      ),
    );
    if (open == true) onOpenDetail();
    return null;
  }
  if (requires.isEmpty) return const TicketMoveInput();

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
