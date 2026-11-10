import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/users/roles_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../shared/empty_state.dart';
import '../shared/skeleton.dart';
import 'user_cards.dart';

/// Pestaña «Roles»: los roles que existen, en solo lectura. Crear, editar o borrar roles y sus
/// permisos se hace desde la web.
class RolesTab extends StatefulWidget {
  const RolesTab({super.key});

  @override
  State<RolesTab> createState() => _RolesTabState();
}

class _RolesTabState extends State<RolesTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Future<void> _refresh(BuildContext context) {
    final done = Completer<void>();
    context.read<RolesBloc>().add(RolesRequested(done: done));
    return done.future;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocBuilder<RolesBloc, RolesState>(
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

  List<Widget> _children(BuildContext context, RolesState state) {
    final bloc = context.read<RolesBloc>();
    if (state.status == RolesStatus.loading) {
      return [Semantics(container: true, label: 'Cargando roles', child: Column(children: [for (var i = 0; i < 3; i++) const Padding(padding: EdgeInsets.only(bottom: AppSpacing.sm), child: Skeleton(height: 84, radius: AppRadius.md))]))];
    }
    if (state.status == RolesStatus.failure) {
      return [EmptyState(icon: Icons.cloud_off_outlined, title: 'No pudimos cargar los roles', message: state.failure?.message, actionLabel: 'Reintentar', onAction: () => bloc.add(const RolesRequested()))];
    }
    if (state.roles.isEmpty) return [const EmptyState(icon: Icons.admin_panel_settings_outlined, title: 'Aún no hay roles')];
    final theme = Theme.of(context);
    return [
      if (state.failure != null)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(children: [
            const Icon(Icons.cloud_off_outlined, size: 18, color: AppColors.slate),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text('No pudimos actualizar la lista.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel))),
            TextButton(onPressed: () => bloc.add(const RolesRequested()), child: const Text('Reintentar')),
          ]),
        ),
      for (final role in state.roles) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: RoleCard(role: role)),
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Text('Para crear o cambiar roles y sus permisos usa la versión web.', textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate)),
      ),
    ];
  }
}
