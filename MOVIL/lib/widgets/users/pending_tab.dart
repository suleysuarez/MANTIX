import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/users/pending_users_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/users/user_models.dart';
import '../shared/empty_state.dart';
import '../shared/skeleton.dart';
import 'user_cards.dart';
import 'users_tones.dart';

/// Pestaña «Pendientes»: las personas que ya iniciaron sesión pero no pueden usar Mantix hasta
/// que alguien les dé un rol. [actionFor] pone el botón de cada tarjeta (por ejemplo «Asignar
/// rol»); si es `null` o devuelve `null`, la tarjeta no lleva acción.
class PendingTab extends StatefulWidget {
  const PendingTab({super.key, this.actionFor});

  final Widget? Function(BuildContext context, PendingUser user)? actionFor;

  @override
  State<PendingTab> createState() => _PendingTabState();
}

class _PendingTabState extends State<PendingTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Future<void> _refresh(BuildContext context) {
    final done = Completer<void>();
    context.read<PendingUsersBloc>().add(PendingUsersRequested(done: done));
    return done.future;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocBuilder<PendingUsersBloc, PendingUsersState>(
      builder: (context, state) => RefreshIndicator(
        color: AppColors.steel,
        onRefresh: () => _refresh(context),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
          children: _children(context, state),
        ),
      ),
    );
  }

  List<Widget> _children(BuildContext context, PendingUsersState state) {
    final bloc = context.read<PendingUsersBloc>();
    if (state.status == PendingStatus.loading) {
      return [
        Semantics(container: true, label: 'Cargando pendientes', child: Column(children: [for (var i = 0; i < 3; i++) const Padding(padding: EdgeInsets.only(bottom: AppSpacing.sm), child: Skeleton(height: 96, radius: AppRadius.md))])),
      ];
    }
    if (state.status == PendingStatus.failure) {
      return [EmptyState(icon: Icons.cloud_off_outlined, title: 'No pudimos cargar los pendientes', message: state.failure?.message, actionLabel: 'Reintentar', onAction: () => bloc.add(const PendingUsersRequested()))];
    }
    if (state.users.isEmpty) {
      return [const EmptyState(icon: Icons.how_to_reg_outlined, title: 'No hay nadie esperando un rol', message: 'Cuando alguien nuevo inicie sesión sin un rol asignado, aparecerá aquí.')];
    }
    final theme = Theme.of(context);
    return [
      Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: mustardTone.background, borderRadius: AppRadius.mdAll),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.error_outline_rounded, size: 20, color: AppColors.navy),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text('Estas personas ya iniciaron sesión, pero no pueden usar Mantix hasta que les asignes un rol.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.navy, height: 1.3))),
        ]),
      ),
      if (state.failure != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Row(children: [
            const Icon(Icons.cloud_off_outlined, size: 18, color: AppColors.slate),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text('No pudimos actualizar la lista.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel))),
            TextButton(onPressed: () => bloc.add(const PendingUsersRequested()), child: const Text('Reintentar')),
          ]),
        ),
      const SizedBox(height: AppSpacing.md),
      for (final user in state.users) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.md), child: PendingUserCard(user: user, action: widget.actionFor?.call(context, user))),
      // Solo quien puede asignar roles ve qué hacer con ellas.
      if (widget.actionFor != null)
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .45), borderRadius: AppRadius.mdAll),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline_rounded, size: 20, color: AppColors.steel),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text('Asigna un rol para habilitar el acceso de la persona.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.navy, height: 1.3))),
          ]),
        ),
    ];
  }
}
