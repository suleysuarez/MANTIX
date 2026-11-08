import 'package:flutter/material.dart';

import '../../core/errors/failure.dart';
import '../../core/theme/app_tokens.dart';

/// Estado de error con reintento. El mensaje viene del [Failure] y nunca trae
/// detalles internos. El código de referencia (`request_id`) ayuda al soporte a
/// encontrar la petición en los logs del servidor.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.failure, this.onRetry});

  final Failure failure;
  final VoidCallback? onRetry;

  static IconData iconOf(Failure failure) => switch (failure) {
        NetworkFailure() => Icons.cloud_off,
        UnauthorizedFailure() || ForbiddenFailure() => Icons.lock_outline,
        NotFoundFailure() => Icons.search_off,
        _ => Icons.error_outline,
      };

  static String titleOf(Failure failure) => switch (failure) {
        NetworkFailure() => 'Sin conexión',
        UnauthorizedFailure() => 'Sesión caducada',
        ForbiddenFailure() => 'Sin permiso',
        NotFoundFailure() => 'No encontrado',
        _ => 'Algo salió mal',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = titleOf(failure);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: theme.colorScheme.error.withValues(alpha: 0.10),
                child: Icon(iconOf(failure), size: 40, color: theme.colorScheme.error, semanticLabel: title),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(failure.message, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
              if (failure.requestId != null) ...[
                const SizedBox(height: AppSpacing.md),
                SelectableText(
                  'Código de referencia: ${failure.requestId}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
