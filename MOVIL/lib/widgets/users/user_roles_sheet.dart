import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/users/assignable_roles_cubit.dart';
import '../../core/format/users_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../shared/empty_state.dart';
import '../shared/error_state.dart';
import '../shared/mantix_sheet.dart';
import '../shared/skeleton.dart';

/// Hoja para elegir los roles de una persona entre los que existen (casillas, de 1 a 10). Sirve
/// para cambiar los roles de alguien y para darle el primero a quien está pendiente.
///
/// Devuelve los ids elegidos, en el orden de la lista de roles, o `null` si se cierra sin
/// confirmar. No manda nada al servidor: quien la abre decide qué hacer con la elección.
Future<List<int>?> showRolesSheet(
  BuildContext context, {
  required AssignableRolesCubit cubit,
  required String title,
  required String subject,
  required Set<int> selected,
  String confirmLabel = 'Guardar roles',
}) =>
    showMantixSheet<List<int>>(
      context,
      title: title,
      initialHeight: .8,
      builder: (sheetContext, controller) => BlocProvider.value(
        value: cubit,
        child: _RolesBody(controller: controller, subject: subject, initial: selected, confirmLabel: confirmLabel),
      ),
    );

class _RolesBody extends StatefulWidget {
  const _RolesBody({required this.controller, required this.subject, required this.initial, required this.confirmLabel});

  final ScrollController controller;
  final String subject;
  final Set<int> initial;
  final String confirmLabel;

  @override
  State<_RolesBody> createState() => _RolesBodyState();
}

class _RolesBodyState extends State<_RolesBody> {
  late final Set<int> _selected = {...widget.initial};

  void _toggle(int id, bool on) => setState(() => on ? _selected.add(id) : _selected.remove(id));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<AssignableRolesCubit, AssignableRolesState>(
      builder: (context, state) {
        final ready = state.status == AssignableRolesStatus.ready;
        final error = ready ? rolesError(_selected) : null;
        return Column(children: [
          Expanded(
            child: ListView(controller: widget.controller, padding: const EdgeInsets.all(AppSpacing.lg), children: [
              Text('Elige los roles de ${widget.subject}.', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.steel)),
              const SizedBox(height: AppSpacing.md),
              ..._content(context, state),
            ]),
          ),
          Container(
            decoration: BoxDecoration(color: AppColors.white, border: Border(top: BorderSide(color: AppColors.grey.withValues(alpha: .6)))),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (ready)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(
                        error ?? (_selected.length == 1 ? '1 rol elegido' : '${_selected.length} roles elegidos'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: error == null ? AppColors.steel : theme.colorScheme.error, fontWeight: FontWeight.w600),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: ready && error == null ? () => Navigator.of(context).pop([for (final role in state.roles) if (_selected.contains(role.id)) role.id]) : null,
                    icon: const Icon(Icons.check_rounded),
                    label: FittedBox(fit: BoxFit.scaleDown, child: Text(widget.confirmLabel, maxLines: 1)),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  ),
                ]),
              ),
            ),
          ),
        ]);
      },
    );
  }

  List<Widget> _content(BuildContext context, AssignableRolesState state) {
    switch (state.status) {
      case AssignableRolesStatus.loading:
        return [for (var i = 0; i < 4; i++) const Padding(padding: EdgeInsets.only(bottom: AppSpacing.sm), child: Skeleton(height: 56, radius: AppRadius.md))];
      case AssignableRolesStatus.failure:
        return [ErrorState(failure: state.failure!, onRetry: () => context.read<AssignableRolesCubit>().load())];
      case AssignableRolesStatus.ready:
        if (state.roles.isEmpty) return [const EmptyState(icon: Icons.admin_panel_settings_outlined, title: 'No hay roles para asignar')];
        return [
          for (final role in state.roles)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              // Material (y no un Container con color): el ListTile pinta su fondo y sus efectos de toque sobre él.
              child: Material(
                color: _selected.contains(role.id) ? AppColors.skyLight.withValues(alpha: .35) : AppColors.white,
                shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: BorderSide(color: _selected.contains(role.id) ? AppColors.steel : AppColors.skyLight.withValues(alpha: .8))),
                clipBehavior: Clip.antiAlias,
                child: CheckboxListTile(
                  value: _selected.contains(role.id),
                  onChanged: (on) => _toggle(role.id, on ?? false),
                  title: Text(role.name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy)),
                  subtitle: Text(role.code, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.slate)),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppColors.steel,
                ),
              ),
            ),
        ];
    }
  }
}
