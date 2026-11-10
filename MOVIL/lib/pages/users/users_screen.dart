import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/users/assignable_roles_cubit.dart';
import '../../bloc/users/pending_users_bloc.dart';
import '../../bloc/users/roles_bloc.dart';
import '../../bloc/users/users_summary_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../repositories/users/users_repository.dart';
import '../../widgets/home/mantix_app_bar.dart';
import '../../widgets/home/mantix_drawer.dart';
import '../../widgets/users/pending_tab.dart';
import '../../widgets/users/roles_tab.dart';
import '../../widgets/users/users_tab.dart';

/// Usuarios y roles en una sola pantalla, con tres pestañas: **Usuarios** (la lista con sus
/// filtros), **Pendientes** (quienes ya entraron y esperan un rol) y **Roles** (los que existen,
/// en solo lectura). Requiere `usuarios:ver`; la ruta lo exige y la autorización real es del
/// backend.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  static const path = '/usuarios';

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late final UsersSummaryBloc _summary;
  late final PendingUsersBloc _pending;
  late final AssignableRolesCubit _assignableRoles;
  RolesBloc? _roles;
  bool? _detailedRoles;

  @override
  void initState() {
    super.initState();
    final repository = context.read<UsersRepository>();
    _summary = UsersSummaryBloc(repository: repository)..add(const UsersSummaryRequested());
    _pending = PendingUsersBloc(repository: repository)..add(const PendingUsersRequested());
    _assignableRoles = AssignableRolesCubit(repository)..load();
  }

  @override
  void dispose() {
    unawaited(_summary.close());
    unawaited(_pending.close());
    unawaited(_assignableRoles.close());
    unawaited(_roles?.close());
    super.dispose();
  }

  /// El bloc de roles depende del permiso de asignar: con él llegan la descripción y el estado.
  RolesBloc _rolesFor(bool detailed) {
    if (_roles == null || _detailedRoles != detailed) {
      unawaited(_roles?.close());
      _roles = RolesBloc(repository: context.read<UsersRepository>(), detailed: detailed)..add(const RolesRequested());
      _detailedRoles = detailed;
    }
    return _roles!;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final profile = auth is Authenticated ? auth.profile : null;
    if (profile == null) {
      return const Scaffold(body: Center(child: Text('No encontramos los datos de tu sesión.')));
    }
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _summary),
        BlocProvider.value(value: _pending),
        BlocProvider.value(value: _assignableRoles),
        BlocProvider.value(value: _rolesFor(profile.can('usuarios:asignar'))),
      ],
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          backgroundColor: AppColors.canvas,
          appBar: MantixAppBar(profile: profile),
          drawer: MantixDrawer(profile: profile, selectedPath: UsersScreen.path),
          body: const Column(children: [
            _Header(),
            _Tabs(),
            Expanded(child: TabBarView(children: [UsersTab(), PendingTab(), RolesTab()])),
          ]),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .5), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.manage_accounts_outlined, color: AppColors.steel, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('USUARIOS Y ROLES', style: TextStyle(color: AppColors.navy, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 0.2))),
              const SizedBox(height: 2),
              Text('Cuentas, personas que esperan un rol y los roles disponibles.', maxLines: 3, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.slate, height: 1.3)),
            ]),
          ),
        ]),
      );
}

/// Las tres pestañas; «Pendientes» lleva el número de personas que esperan un rol.
class _Tabs extends StatelessWidget {
  const _Tabs();

  @override
  Widget build(BuildContext context) {
    // La lista de pendientes manda cuando ya cargó; antes, la cifra del resumen.
    final waiting = context.select((PendingUsersBloc bloc) => bloc.state.status == PendingStatus.ready ? bloc.state.users.length : null) ?? context.select((UsersSummaryBloc bloc) => bloc.state.summary?.withoutRole) ?? 0;
    return TabBar(
      labelColor: AppColors.navy,
      unselectedLabelColor: AppColors.steel,
      indicatorColor: AppColors.mustard,
      indicatorWeight: 3,
      dividerColor: AppColors.skyLight,
      labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
      tabs: [
        const Tab(child: FittedBox(fit: BoxFit.scaleDown, child: Text('Usuarios'))),
        Tab(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('Pendientes'),
              if (waiting > 0) ...[
                const SizedBox(width: 6),
                Semantics(
                  label: waiting == 1 ? '1 persona espera un rol' : '$waiting personas esperan un rol',
                  excludeSemantics: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.mustard, borderRadius: AppRadius.pillAll),
                    child: Text('$waiting', style: const TextStyle(color: AppColors.navy, fontSize: 11, fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ]),
          ),
        ),
        const Tab(child: FittedBox(fit: BoxFit.scaleDown, child: Text('Roles'))),
      ],
    );
  }
}
