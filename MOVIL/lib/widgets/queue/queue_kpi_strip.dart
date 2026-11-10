import 'package:flutter/material.dart';

import '../../core/format/queue_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/queue/queue_models.dart';
import '../shared/skeleton.dart';

/// Fila horizontal de tarjetas con las cifras de la cola: en cola, sin técnico, la más antigua
/// y la espera mediana. Con [summary] en `null` muestra esqueletos (o «no disponible» si
/// [unavailable]) y el reintento.
class QueueKpiStrip extends StatefulWidget {
  const QueueKpiStrip({super.key, required this.summary, required this.unavailable, required this.onRetry});

  final QueueSummary? summary;
  final bool unavailable;
  final VoidCallback onRetry;

  @override
  State<QueueKpiStrip> createState() => _QueueKpiStripState();
}

class _QueueKpiStripState extends State<QueueKpiStrip> {
  final _controller = ScrollController();
  bool _atEnd = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    final atEnd = _controller.hasClients && _controller.position.pixels >= _controller.position.maxScrollExtent - 4;
    if (atEnd != _atEnd) setState(() => _atEnd = atEnd);
  }

  /// La flecha avanza una tarjeta y, al llegar al final, vuelve al principio.
  void _scroll() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target = _atEnd ? 0.0 : (position.pixels + _KpiCard.width + AppSpacing.sm).clamp(0.0, position.maxScrollExtent);
    _controller.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    if (summary == null && widget.unavailable) {
      return _Unavailable(message: 'Las cifras de la cola no están disponibles.', onRetry: widget.onRetry);
    }
    final cards = summary == null
        ? [for (var i = 0; i < 4; i++) const _KpiCard.loading()]
        : [
            _KpiCard(label: 'EN COLA', value: '${summary.pendingTotal}', caption: summary.pendingTotal == 1 ? 'solicitud' : 'solicitudes', icon: Icons.inbox_outlined),
            _KpiCard(label: 'SIN TÉCNICO', value: '${summary.unassigned}', caption: 'esperan asignación', icon: Icons.person_off_outlined),
            _KpiCard(label: 'MÁS ANTIGUA', value: formatHours(summary.oldestWaitHours), caption: 'en la cola', icon: Icons.hourglass_top_rounded),
            // El servidor entrega la mediana, no la media: se rotula como la web.
            _KpiCard(label: 'ESPERA MEDIANA', value: formatHours(summary.medianWaitHours), caption: 'de las pendientes', icon: Icons.timelapse_rounded),
          ];
    return SizedBox(
      height: _KpiCard.height,
      child: Stack(children: [
        ListView.separated(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(right: 48),
          itemCount: cards.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (_, index) => cards[index],
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: Center(
            child: IconButton.filledTonal(
              tooltip: _atEnd ? 'Volver al inicio' : 'Ver más cifras',
              onPressed: _scroll,
              icon: Icon(_atEnd ? Icons.chevron_left_rounded : Icons.chevron_right_rounded),
            ),
          ),
        ),
      ]),
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

  static const width = 150.0;
  static const height = 112.0;

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
        width: width,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.lgAll, border: Border.all(color: AppColors.grey)),
        child: label == null
            ? const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Skeleton(width: 80, height: 10), SizedBox(height: 14), Skeleton(width: 60, height: 26), SizedBox(height: 12), Skeleton(width: 100, height: 10)])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(icon, size: 15, color: AppColors.slate),
                  const SizedBox(width: 6),
                  Expanded(child: Text(label!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w800, letterSpacing: 0.6))),
                ]),
                const Spacer(),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value!, style: theme.textTheme.headlineSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900))),
                Text(caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate)),
              ]),
      ),
    );
  }
}

/// «No disponible» con reintento: el resto de la pantalla sigue funcionando.
class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.lgAll, border: Border.all(color: AppColors.grey)),
        child: Row(children: [
          const Icon(Icons.cloud_off_outlined, color: AppColors.slate),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.steel))),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ]),
      );
}

/// El mismo aviso para otras tarjetas del resumen.
class QueueUnavailable extends StatelessWidget {
  const QueueUnavailable({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _Unavailable(message: message, onRetry: onRetry);
}
