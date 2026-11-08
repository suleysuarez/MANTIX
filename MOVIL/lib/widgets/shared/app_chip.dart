import 'package:flutter/material.dart';

import '../../core/domain/ticket_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

/// Chip de solo lectura con punto indicador. Un lector de pantalla lo anuncia
/// como una sola frase («Estado: Resuelto»); el color nunca es la única señal.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    required this.colors,
    this.strikethrough = false,
    this.semanticPrefix,
  });

  final String label;
  final ChipColors colors;
  final bool strikethrough;

  /// Se antepone al anunciar el chip: «Estado», «Prioridad».
  final String? semanticPrefix;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colors.foreground,
          fontWeight: FontWeight.w700,
          decoration: strikethrough ? TextDecoration.lineThrough : null,
          decorationColor: colors.foreground,
        );
    return Semantics(
      label: semanticPrefix == null ? label : '$semanticPrefix: $label',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.background, borderRadius: AppRadius.pillAll),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs + 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(color: colors.dot, shape: BoxShape.circle),
                child: const SizedBox.square(dimension: 8),
              ),
              const SizedBox(width: AppSpacing.sm - 2),
              Flexible(child: Text(label, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Estado de un ticket. Un código desconocido se muestra tal cual, en neutro.
class StatusChip extends StatelessWidget {
  const StatusChip(this.code, {super.key});

  final String code;

  @override
  Widget build(BuildContext context) {
    final meta = statusMeta(code);
    return AppChip(
      label: meta.label,
      colors: meta.colors,
      strikethrough: meta.strikethrough,
      semanticPrefix: 'Estado',
    );
  }
}

/// Prioridad de un ticket.
class PriorityChip extends StatelessWidget {
  const PriorityChip(this.code, {super.key});

  final String code;

  @override
  Widget build(BuildContext context) {
    final meta = priorityMeta(code);
    return AppChip(label: meta.label, colors: meta.colors, semanticPrefix: 'Prioridad');
  }
}
