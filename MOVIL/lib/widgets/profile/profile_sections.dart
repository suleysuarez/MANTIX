import 'package:flutter/material.dart';

import '../../bloc/paged/paged_bloc.dart';
import '../../core/format/formatters.dart';
import '../../core/format/profile_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/profile/profile_models.dart';
import '../shared/empty_state.dart';
import '../shared/skeleton.dart';

/// Una fila de datos: icono, nombre del dato y su valor. Sin valor sale «Sin registrar» en gris.
typedef InfoRow = (IconData icon, String label, String? value);

/// Tarjeta blanca con los datos de la persona, una fila por dato.
class ProfileInfoCard extends StatelessWidget {
  const ProfileInfoCard({super.key, required this.rows});

  final List<InfoRow> rows;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.skyLight.withValues(alpha: .75))),
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.grey.withValues(alpha: .5)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(rows[i].$1, size: 19, color: AppColors.steel),
                const SizedBox(width: 10),
                SizedBox(width: 96, child: Text(rows[i].$2, style: const TextStyle(color: AppColors.steel, fontSize: 12.5, fontWeight: FontWeight.w700))),
                Expanded(
                  child: Text(
                    (rows[i].$3 ?? '').trim().isEmpty ? 'Sin registrar' : rows[i].$3!,
                    style: TextStyle(color: (rows[i].$3 ?? '').trim().isEmpty ? AppColors.slate : AppColors.navy, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
            ),
          ],
        ]),
      );
}

/// Título de sección con la barra mostaza de la app.
class ProfileSectionTitle extends StatelessWidget {
  const ProfileSectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(width: 4, height: 18, decoration: BoxDecoration(color: AppColors.mustard, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 8),
        Expanded(child: Semantics(header: true, child: Text(title, style: const TextStyle(color: AppColors.navy, fontSize: 16, fontWeight: FontWeight.w900)))),
        ?trailing,
      ]);
}

IconData _kindIcon(String kind) => switch (kind) {
      'session' => Icons.login_rounded,
      'profile' => Icons.person_outline_rounded,
      'security' => Icons.shield_outlined,
      _ => Icons.bolt_outlined,
    };

/// «Mi actividad»: las últimas acciones sobre mi cuenta, con cargando, vacío y error con
/// reintento. «Ver más» pide la página siguiente.
class ProfileHistorySection extends StatelessWidget {
  const ProfileHistorySection({super.key, required this.state, required this.onMore, required this.onRetry});

  final PagedListState<HistoryEntry> state;
  final VoidCallback onMore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const ProfileSectionTitle('Mi actividad'),
      const SizedBox(height: AppSpacing.sm),
      if (state.status == PagedStatus.loading && state.items.isEmpty)
        Semantics(container: true, label: 'Cargando tu actividad', child: const Column(children: [Skeleton(height: 56, radius: AppRadius.md), SizedBox(height: AppSpacing.sm), Skeleton(height: 56, radius: AppRadius.md)]))
      else if (state.status == PagedStatus.failure && state.items.isEmpty)
        EmptyState(icon: Icons.cloud_off_outlined, title: 'No pudimos cargar tu actividad', message: state.failure?.message, actionLabel: 'Reintentar', onAction: onRetry)
      else if (state.items.isEmpty)
        const EmptyState(icon: Icons.history_rounded, title: 'Aún no hay actividad', message: 'Tus inicios de sesión y los cambios en tu cuenta aparecerán aquí.')
      else ...[
        for (final entry in state.items)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.skyLight.withValues(alpha: .75))),
            child: Row(children: [
              Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .5), shape: BoxShape.circle), child: Icon(_kindIcon(entry.kind), size: 19, color: AppColors.steel)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(historyTitle(entry.action), style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)),
                  Text(
                    [formatDateTime(entry.createdAt), if (entry.actorName != null) 'por ${entry.actorName}'].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate),
                  ),
                ]),
              ),
              const SizedBox(width: 6),
              Text(historyKindLabel(entry.kind), style: theme.textTheme.labelSmall?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w700)),
            ]),
          ),
        if (state.loadingMore)
          const Padding(padding: EdgeInsets.all(AppSpacing.md), child: Center(child: CircularProgressIndicator(color: AppColors.steel, strokeWidth: 2.5)))
        else if (state.hasMore)
          TextButton(onPressed: onMore, child: const Text('Ver más'))
        else if (state.loadMoreFailure != null)
          Column(children: [
            Text(state.loadMoreFailure!.message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error, fontSize: 12)),
            TextButton(onPressed: onMore, child: const Text('Reintentar')),
          ]),
      ],
    ]);
  }
}
