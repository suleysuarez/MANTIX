import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/users/assignable_roles_cubit.dart';
import '../../bloc/users/pending_users_bloc.dart';
import '../../bloc/users/roles_bloc.dart';
import '../../bloc/users/user_actions_bloc.dart';
import '../../bloc/users/users_summary_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/users/user_models.dart';
import '../../repositories/users/users_repository.dart';
import '../../widgets/home/mantix_app_bar.dart';
import '../../widgets/home/mantix_drawer.dart';
import '../../widgets/users/pending_tab.dart';
import '../../widgets/users/roles_tab.dart';
import '../../widgets/users/user_detail_sheet.dart';
import '../../widgets/users/user_roles_sheet.dart';
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
  late final UserActionsBloc _actions;
  RolesBloc? _roles;
  bool? _detailedRoles;

  @override
  void initState() {
    super.initState();
    final repository = context.read<UsersRepository>();
    _summary = UsersSummaryBloc(repository: repository)..add(const UsersSummaryRequested());
    _pending = PendingUsersBloc(repository: repository)..add(const PendingUsersRequested());
    _assignableRoles = AssignableRolesCubit(repository)..load();
    // Quien usa la app no puede desactivar su propia cuenta.
    final auth = context.read<AuthBloc>().state;
    _actions = UserActionsBloc(repository: repository, currentUserId: auth is Authenticated ? auth.profile.id : -1);
  }

  @override
  void dispose() {
    unawaited(_summary.close());
    unawaited(_pending.close());
    unawaited(_assignableRoles.close());
    unawaited(_actions.close());
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

  /// Da el primer rol (o más) a una persona pendiente.
  Future<void> _assignRole(PendingUser user) async {
    final ids = await showRolesSheet(context, cubit: _assignableRoles, title: 'Asignar rol', subject: user.fullName, selected: const {}, confirmLabel: 'Asignar roles');
    if (ids == null || !mounted) return;
    _actions.add(UserRolesChangeRequested(userId: user.id, name: user.fullName, roleIds: ids));
  }

  /// El resultado de cada acción en un aviso: navy si salió bien, rojo si no.
  void _onOutcome(BuildContext context, UserActionsState state) {
    final outcome = state.outcome!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(outcome.message), backgroundColor: outcome.isError ? AppColors.error : AppColors.navy));
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
        BlocProvider.value(value: _actions),
        BlocProvider.value(value: _rolesFor(profile.can('usuarios:asignar'))),
      ],
      child: BlocListener<UserActionsBloc, UserActionsState>(
        listenWhen: (previous, current) => current.outcome != null && previous.outcome != current.outcome,
        listener: _onOutcome,
        child: DefaultTabController(
          length: 3,
          child: Scaffold(
            backgroundColor: AppColors.canvas,
            appBar: MantixAppBar(profile: profile),
            drawer: MantixDrawer(profile: profile, selectedPath: UsersScreen.path),
            body: Column(children: [
              const _Header(),
              const _Tabs(),
              Expanded(
                child: TabBarView(children: [
                  UsersTab(
                    onOpen: (user) => showUserDetail(
                      context,
                      user: user,
                      actions: _actions,
                      rolesCubit: _assignableRoles,
                      currentUserId: profile.id,
                      can: UserPermissions(canAssignRoles: profile.can('usuarios:asignar'), canEdit: profile.can('usuarios:editar'), canChangeStatus: profile.can('usuarios:cambiar_estado')),
                    ),
                  ),
                  PendingTab(actionFor: profile.can('usuarios:asignar') ? (context, user) => _AssignButton(onPressed: () => _assignRole(user), userId: user.id) : null),
                  const RolesTab(),
                ]),
              ),
            ]),
          ),
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

/// «Asignar rol» de una persona pendiente; se apaga mientras se le está asignando.
class _AssignButton extends StatelessWidget {
  const _AssignButton({required this.onPressed, required this.userId});

  final VoidCallback onPressed;
  final int userId;

  @override
  Widget build(BuildContext context) {
    final busy = context.select((UserActionsBloc bloc) => bloc.state.inFlight.contains(userId));
    return FilledButton.tonalIcon(
      onPressed: busy ? null : onPressed,
      icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.admin_panel_settings_outlined, size: 18),
      label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Asignar rol', maxLines: 1)),
      style: FilledButton.styleFrom(backgroundColor: AppColors.mustard, foregroundColor: AppColors.navy, minimumSize: const Size.fromHeight(46)),
    );
  }
}
