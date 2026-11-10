import 'package:flutter/material.dart';

import '../../core/format/queue_format.dart';
import '../../models/users/user_models.dart';
import '../shared/filter_widgets.dart';

/// Los filtros de la lista de usuarios: rol (por su código), estado de la cuenta y fecha de
/// creación. Vacíos no filtran.
class UsersFilters {
  const UsersFilters({this.role, this.isActive, this.dates});

  /// Código del rol (por ejemplo, `TECHNICIAN`).
  final String? role;

  /// `true`: solo cuentas activas; `false`: solo inactivas; `null`: todas.
  final bool? isActive;
  final DateTimeRange? dates;

  /// Cuántos filtros hay puestos (para el contador del botón).
  int get activeCount => (role == null ? 0 : 1) + (isActive == null ? 0 : 1) + (dates == null ? 0 : 1);

  @override
  bool operator ==(Object other) => other is UsersFilters && other.role == role && other.isActive == isActive && other.dates == dates;

  @override
  int get hashCode => Object.hash(role, isActive, dates);
}

/// Hoja de filtros de usuarios. Devuelve los filtros al aplicar y `null` si se cierra sin aplicar
/// (no cambia nada). [roles] son los que se pueden elegir; si aún no cargaron, solo «Todos».
Future<UsersFilters?> showUsersFilterSheet(BuildContext context, {required UsersFilters initial, required List<UserRoleRef> roles, DateTime? today}) => showModalBottomSheet<UsersFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _UsersFilterSheet(initial: initial, roles: roles, today: today ?? DateTime.now()),
    );

class _UsersFilterSheet extends StatefulWidget {
  const _UsersFilterSheet({required this.initial, required this.roles, required this.today});

  final UsersFilters initial;
  final List<UserRoleRef> roles;
  final DateTime today;

  @override
  State<_UsersFilterSheet> createState() => _UsersFilterSheetState();
}

class _UsersFilterSheetState extends State<_UsersFilterSheet> {
  late String? _role = widget.roles.any((role) => role.code == widget.initial.role) ? widget.initial.role : null;
  late bool? _isActive = widget.initial.isActive;
  late DateTimeRange? _dates = widget.initial.dates;

  /// Mismo criterio de todos los filtros por fechas: la inicial no es futura, la final no es
  /// anterior y como máximo 366 días.
  String? get _rangeError => queueRangeError(_dates?.start, _dates?.end, widget.today);

  @override
  Widget build(BuildContext context) {
    final error = _rangeError;
    return FilterSheet(
      onReset: () => setState(() {
        _role = null;
        _isActive = null;
        _dates = null;
      }),
      onApply: error == null ? () => Navigator.pop(context, UsersFilters(role: _role, isActive: _isActive, dates: _dates)) : null,
      children: [
        FilterDropdown<String?>(
          label: 'Rol',
          icon: Icons.admin_panel_settings_outlined,
          value: _role,
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Todos los roles')),
            for (final role in widget.roles) DropdownMenuItem<String?>(value: role.code, child: Text(role.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (value) => setState(() => _role = value),
        ),
        FilterDropdown<bool?>(
          label: 'Estado de la cuenta',
          icon: Icons.flag_outlined,
          value: _isActive,
          items: const [
            DropdownMenuItem<bool?>(value: null, child: Text('Todas')),
            DropdownMenuItem<bool?>(value: true, child: Text('Activas')),
            DropdownMenuItem<bool?>(value: false, child: Text('Inactivas')),
          ],
          onChanged: (value) => setState(() => _isActive = value),
        ),
        DateRangeFilterField(label: 'Fecha de creación', value: _dates, onChanged: (range) => setState(() => _dates = range)),
        if (error != null) Text(error, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
      ],
    );
  }
}
