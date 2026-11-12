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
import '../../models/users/user_models.dart';
import '../../repositories/users/users_repository.dart';
import '../../widgets/home/mantix_app_bar.dart';
import '../../widgets/home/mantix_drawer.dart';
import '../../widgets/users/pending_tab.dart';
import '../../widgets/users/roles_tab.dart';
import '../../widgets/users/user_detail_sheet.dart';
import '../../widgets/users/user_roles_sheet.dart';
import '../../widgets/users/users_header.dart';
import '../../widgets/users/users_tab_pills.dart';
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
              const _TabsHeader(),
              const _Pills(),
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

/// El encabezado cambia con la pestaña: el icono, el título y la explicación de lo que se ve.
class _TabsHeader extends StatelessWidget {
  const _TabsHeader();

  static const _icons = [Icons.groups_outlined, Icons.schedule_rounded, Icons.verified_user_outlined];
  static const _titles = ['Usuarios y Roles', 'Pendientes', 'Roles'];
  static const _subtitles = [
    'Gestiona usuarios y roles de la plataforma.',
    'Personas que esperan tu aprobación.',
    'Los roles del sistema y cuántas personas tiene cada uno.',
  ];

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    final animation = controller.animation ?? controller;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final index = (controller.animation?.value ?? controller.index.toDouble()).round().clamp(0, 2);
        return UsersHeader(icon: _icons[index], title: _titles[index], subtitle: _subtitles[index]);
      },
    );
  }
}

/// Las tres pestañas como píldoras; «Pendientes» lleva el número de personas que esperan un rol.
class _Pills extends StatelessWidget {
  const _Pills();

  @override
  Widget build(BuildContext context) {
    // La lista de pendientes manda cuando ya cargó; antes, la cifra del resumen.
    final waiting = context.select((PendingUsersBloc bloc) => bloc.state.status == PendingStatus.ready ? bloc.state.users.length : null) ?? context.select((UsersSummaryBloc bloc) => bloc.state.summary?.withoutRole) ?? 0;
    return UsersTabPills(controller: DefaultTabController.of(context), pendingCount: waiting);
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
    return FilledButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.person_add_alt_1_outlined, size: 20),
      label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Asignar rol', maxLines: 1)),
      style: FilledButton.styleFrom(backgroundColor: AppColors.mustard, foregroundColor: AppColors.navy, minimumSize: const Size.fromHeight(54), textStyle: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}
