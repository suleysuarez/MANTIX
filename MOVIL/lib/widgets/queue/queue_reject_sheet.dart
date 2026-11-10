import 'package:flutter/material.dart';

import '../../core/format/queue_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/requests/request_models.dart';
import '../shared/mantix_sheet.dart';

/// Hoja para rechazar una solicitud: pide el motivo (de 5 a 500 caracteres, sin contar los
/// espacios sobrantes). Devuelve el motivo recortado o `null` si se cierra sin confirmar.
Future<String?> showRejectSheet(BuildContext context, {required TicketListItem ticket}) => showMantixSheet<String>(
  context,
  title: 'Rechazar solicitud',
  initialHeight: .7,
  builder: (sheetContext, controller) => _RejectBody(ticket: ticket, controller: controller),
);

class _RejectBody extends StatefulWidget {
  const _RejectBody({required this.ticket, required this.controller});

  final TicketListItem ticket;
  final ScrollController controller;

  @override
  State<_RejectBody> createState() => _RejectBodyState();
}

class _RejectBodyState extends State<_RejectBody> {
  final _reason = TextEditingController();

  /// El error solo se muestra cuando la persona ya escribió algo (o intentó confirmar).
  bool _touched = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _confirm() {
    if (reasonError(_reason.text) != null) {
      setState(() => _touched = true);
      return;
    }
    Navigator.of(context).pop(_reason.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = reasonError(_reason.text);
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: widget.controller,
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(
                widget.ticket.ticketNumber,
                style: theme.textTheme.labelLarge?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                widget.ticket.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Quien la pidió verá este motivo en el historial.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate)),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _reason,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                maxLength: maxReasonLength,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() => _touched = true),
                decoration: InputDecoration(labelText: 'Motivo del rechazo', hintText: 'Por ejemplo: duplicada de otra solicitud', errorText: _touched ? error : null, errorMaxLines: 2),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            border: Border(top: BorderSide(color: AppColors.grey.withValues(alpha: .6))),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: FilledButton.icon(
                onPressed: _confirm,
                icon: const Icon(Icons.block_rounded),
                label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Rechazar solicitud', maxLines: 1)),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: AppColors.error, foregroundColor: AppColors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
