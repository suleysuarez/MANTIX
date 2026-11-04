import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';

/// Estado vacío: aún no hay datos, o los filtros no devolvieron nada.
///
/// Muestra un icono por defecto. Cuando haya ilustraciones, se pasan en
/// [illustration] sin tocar las pantallas.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.illustration,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? message;
  final IconData icon;

  /// Sustituye al icono (por ejemplo, un `Image.asset`).
  final Widget? illustration;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              illustration ??
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                    child: Icon(icon, size: 40, color: theme.colorScheme.primary),
                  ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (message != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(message!, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.xl),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
