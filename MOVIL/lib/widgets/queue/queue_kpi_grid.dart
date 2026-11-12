import 'package:flutter/material.dart';

import '../../core/format/queue_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/queue/queue_models.dart';
import '../shared/skeleton.dart';

/// Cuatro cifras de la cola (en cola, sin técnico, la más antigua y la espera mediana) en un
/// cuadro de dos por dos, todas del mismo tamaño y sin desplazamiento. Con [summary] en `null`
/// muestra esqueletos (o «no disponible» con reintento si [unavailable]).
class QueueKpiGrid extends StatelessWidget {
  const QueueKpiGrid({super.key, required this.summary, required this.unavailable, required this.onRetry});

  final QueueSummary? summary;
  final bool unavailable;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final data = summary;
    if (data == null && unavailable) {
      return QueueUnavailable(message: 'Las cifras de la cola no están disponibles.', onRetry: onRetry);
    }
    final cards = data == null
        ? [for (var i = 0; i < 4; i++) const _KpiCard.loading()]
        : [
            _KpiCard(label: 'EN COLA', value: '${data.pendingTotal}', caption: data.pendingTotal == 1 ? 'solicitud' : 'solicitudes', icon: Icons.inbox_outlined),
            _KpiCard(label: 'SIN TÉCNICO', value: '${data.unassigned}', caption: 'esperan asignación', icon: Icons.person_off_outlined),
            _KpiCard(label: 'MÁS ANTIGUA', value: formatHours(data.oldestWaitHours), caption: 'en la cola', icon: Icons.hourglass_top_rounded),
            // El servidor entrega la mediana, no la media: se rotula como la web.
            _KpiCard(label: 'ESPERA MEDIANA', value: formatHours(data.medianWaitHours), caption: 'de las pendientes', icon: Icons.timelapse_rounded),
          ];
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // Dos por fila y del mismo alto; el alto crece con el tamaño de letra del sistema para que nada se corte.
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
        mainAxisExtent: 102 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
      ),
      children: cards,
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.value, required this.caption, required this.icon});

  const _KpiCard.loading()
      : label = null,
        value = null,
        caption = null,
        icon = null;

  final String? label;
  final String? value;
  final String? caption;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: label == null ? 'Cargando' : '$label: $value, $caption',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: AppColors.skyLight.withValues(alpha: .7)),
          boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: .06), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm + 2),
              child: label == null
                  ? const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Skeleton(width: 80, height: 10), Spacer(), Skeleton(width: 60, height: 26), SizedBox(height: 8), Skeleton(width: 100, height: 10)])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .5), borderRadius: AppRadius.smAll),
                          child: Icon(icon, size: 15, color: AppColors.steel),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(label!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w800, letterSpacing: 0.4))),
                      ]),
                      const Spacer(),
                      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value!, style: theme.textTheme.titleLarge?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900))),
                      Text(caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel)),
                    ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// «No disponible» con reintento: el resto de la pantalla sigue funcionando.
class QueueUnavailable extends StatelessWidget {
  const QueueUnavailable({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.lgAll, border: Border.all(color: AppColors.skyLight.withValues(alpha: .7))),
        child: Row(children: [
          const Icon(Icons.cloud_off_outlined, color: AppColors.slate),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.steel))),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ]),
      );
}
