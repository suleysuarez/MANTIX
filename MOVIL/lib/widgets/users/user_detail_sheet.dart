import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/users/assignable_roles_cubit.dart';
import '../../bloc/users/user_actions_bloc.dart';
import '../../core/format/formatters.dart';
import '../../core/format/users_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/users/user_models.dart';
import '../shared/app_chip.dart';
import '../shared/confirm_dialog.dart';
import '../shared/detail_parts.dart';
import '../shared/mantix_sheet.dart';
import 'user_cards.dart';
import 'user_contact_sheet.dart';
import 'user_roles_sheet.dart';
import 'users_tones.dart';

/// Qué puede hacer quien usa la app con una persona; cada botón sale solo con su permiso
/// (se decide por los permisos efectivos de `/auth/me`, nunca por el nombre del rol).
class UserPermissions {
  const UserPermissions({this.canAssignRoles = false, this.canEdit = false, this.canChangeStatus = false});

  /// `usuarios:asignar`.
  final bool canAssignRoles;

  /// `usuarios:editar`.
  final bool canEdit;

  /// `usuarios:cambiar_estado`.
  final bool canChangeStatus;
}

/// Ficha de una persona en una hoja inferior arrastrable: sus datos y, según los permisos,
/// cambiar sus roles, editar el teléfono, y activar o desactivar su cuenta. Al terminar una
/// acción bien la hoja se cierra y el aviso lo da la pantalla; si falla, el motivo sale dentro
/// de la hoja y la persona sigue donde estaba.
Future<void> showUserDetail(
  BuildContext context, {
  required ManagedUser user,
  required UserActionsBloc actions,
  required AssignableRolesCubit rolesCubit,
  required UserPermissions can,
  required int currentUserId,
  DateTime? now,
}) =>
    showMantixSheet<void>(
      context,
      title: 'Detalle del usuario',
      builder: (sheetContext, controller) => BlocProvider.value(
        value: actions,
        child: _UserDetail(user: user, controller: controller, rolesCubit: rolesCubit, can: can, currentUserId: currentUserId, now: now),
      ),
    );

class _UserDetail extends StatefulWidget {
  const _UserDetail({required this.user, required this.controller, required this.rolesCubit, required this.can, required this.currentUserId, this.now});

  final ManagedUser user;
  final ScrollController controller;
  final AssignableRolesCubit rolesCubit;
  final UserPermissions can;
  final int currentUserId;
  final DateTime? now;

  @override
  State<_UserDetail> createState() => _UserDetailState();
}

class _UserDetailState extends State<_UserDetail> {
  /// Último error de una acción sobre esta persona, para enseñarlo dentro de la hoja.
  String? _error;

  ManagedUser get _user => widget.user;
  UserActionsBloc get _actions => context.read<UserActionsBloc>();
  bool get _isMe => _user.id == widget.currentUserId;

  void _onOutcome(BuildContext context, UserActionsState state) {
    final outcome = state.outcome;
    if (outcome == null || outcome.userId != _user.id) return;
    if (outcome.kind == UserOutcomeKind.succeeded) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _error = outcome.message);
    }
  }

  Future<void> _changeRoles() async {
    final ids = await showRolesSheet(context, cubit: widget.rolesCubit, title: 'Roles de ${_user.fullName}', subject: _user.fullName, selected: {for (final role in _user.roles) role.id});
    if (ids == null || !mounted) return;
    setState(() => _error = null);
    _actions.add(UserRolesChangeRequested(userId: _user.id, name: _user.fullName, roleIds: ids, currentRoleIds: [for (final role in _user.roles) role.id]));
  }

  Future<void> _edit() async {
    final input = await showContactSheet(context, user: _user);
    if (input == null || !mounted) return;
    setState(() => _error = null);
    _actions.add(UserContactChangeRequested(_user, phone: input.phone));
  }

  Future<void> _toggle() async {
    if (_user.isActive) {
      final ok = await showConfirmDialog(
        context,
        title: '¿Desactivar a ${_user.fullName}?',
        message: 'No podrá iniciar sesión mientras su cuenta esté desactivada. Puedes reactivarla cuando quieras.',
        confirmLabel: 'Desactivar',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _error = null);
    _actions.add(UserActiveChangeRequested(_user, active: !_user.isActive));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = accessState(isActive: _user.isActive, lastLoginAt: _user.lastLoginAt);
    final now = widget.now ?? DateTime.now();
    return BlocConsumer<UserActionsBloc, UserActionsState>(
      listenWhen: (previous, current) => current.outcome != null && previous.outcome != current.outcome,
      listener: _onOutcome,
      builder: (context, actionState) {
        final busy = actionState.inFlight.contains(_user.id);
        final canToggle = widget.can.canChangeStatus && !(_isMe && _user.isActive);
        return ListView(
          controller: widget.controller,
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
          children: [
            DetailHeader(
              icon: Icons.person_outline_rounded,
              title: _user.fullName,
              chips: [
                AppChip(label: accessLabel(state), colors: accessColors(state), semanticPrefix: 'Estado'),
                if (_isMe) RoleChip('Eres tú', tone: mustardTone),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(color: theme.colorScheme.errorContainer, borderRadius: AppRadius.mdAll),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.error_outline_rounded, size: 18, color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onErrorContainer, height: 1.3))),
                ]),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            DetailSection(icon: Icons.admin_panel_settings_outlined, title: 'Roles', children: [
              if (_user.roles.isEmpty)
                Text('Todavía no tiene un rol: no puede usar Mantix.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel))
              else
                Wrap(spacing: 6, runSpacing: 6, children: [for (final role in _user.roles) RoleChip(role.name)]),
            ]),
            const SizedBox(height: AppSpacing.md),
            DetailSection(icon: Icons.info_outline_rounded, title: 'Datos de la cuenta', children: [
              DetailField('Correo', _user.email),
              DetailField('Teléfono', _user.phone ?? 'Sin registrar'),
              DetailField('Creada', formatDate(_user.createdAt)),
              DetailField('Último acceso', lastAccessText(_user.lastLoginAt, now)),
            ]),
            if (widget.can.canAssignRoles || widget.can.canEdit || canToggle || (_isMe && widget.can.canChangeStatus)) ...[
              const SizedBox(height: AppSpacing.lg),
              if (widget.can.canAssignRoles) FilledButton.icon(onPressed: busy ? null : _changeRoles, icon: const Icon(Icons.admin_panel_settings_outlined), label: const Text('Cambiar roles'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50))),
              if (widget.can.canEdit) ...[
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(onPressed: busy ? null : _edit, icon: const Icon(Icons.edit_outlined), label: const Text('Editar teléfono'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50))),
              ],
              if (canToggle) ...[
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: busy ? null : _toggle,
                  icon: Icon(_user.isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded),
                  label: Text(_user.isActive ? 'Desactivar cuenta' : 'Activar cuenta'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), foregroundColor: _user.isActive ? theme.colorScheme.error : AppColors.steel),
                ),
              ] else if (_isMe && widget.can.canChangeStatus)
                Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: Text('No puedes desactivar tu propia cuenta.', textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate))),
              if (busy) const Padding(padding: EdgeInsets.only(top: AppSpacing.md), child: LinearProgressIndicator(minHeight: 3)),
            ],
          ],
        );
      },
    );
  }
}
