import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../pages/queue/pending_requests_screen.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../core/routing/home_resolver.dart';
import '../../core/theme/app_colors.dart';
import '../../models/auth/user_profile.dart';
import 'brand_logo.dart';

/// Iniciales (hasta dos) de un nombre; «M» si no hay ninguna.
String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).take(2);
  final value = parts.map((part) => part[0].toUpperCase()).join();
  return value.isEmpty ? 'M' : value;
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.path, [this.permission, this.anyPermissions = const []]);
  final String label;
  final IconData icon;
  final String path;
  final String? permission;
  final List<String> anyPermissions;
}

/// Menú lateral. Solo muestra los módulos para los que el usuario tiene permiso (se
/// decide por permisos efectivos, nunca por el nombre del rol).
class MantixDrawer extends StatelessWidget {
  const MantixDrawer({super.key, required this.profile, required this.selectedPath});

  final UserProfile profile;

  /// Ruta de la pantalla actual: su elemento del menú queda resaltado.
  final String selectedPath;

  static const _navItems = <_NavItem>[
    _NavItem('Dashboard', Icons.home_rounded, '/inicio/dashboard-global'),
    _NavItem('Equipos', Icons.desktop_windows_rounded, '/modulos/equipos', 'equipos:ver'),
    _NavItem('Tickets', Icons.confirmation_number_outlined, '/modulos/tickets', 'tickets:ver'),
    _NavItem('Solicitudes', Icons.inbox_outlined, '/inicio/solicitudes', null, ['solicitudes:ver', 'solicitudes:ver_todos']),
    _NavItem('Solicitudes pendientes', Icons.move_to_inbox_outlined, PendingRequestsScreen.path, 'solicitudes:ver_todos'),
    _NavItem('Técnicos', Icons.engineering_outlined, '/modulos/tecnicos', 'tecnicos:ver'),
    _NavItem('Mantenimiento', Icons.event_repeat_rounded, '/modulos/mantenimiento', 'mantenimiento:ver'),
    _NavItem('Inventario', Icons.inventory_2_outlined, '/modulos/inventario', 'inventario:ver'),
    _NavItem('Reportes', Icons.analytics_rounded, '/inicio/reportes', 'reportes:ver'),
    _NavItem('Usuarios', Icons.manage_accounts_outlined, '/modulos/usuarios', 'usuarios:ver'),
    _NavItem('Roles y permisos', Icons.admin_panel_settings_outlined, '/modulos/roles', 'usuarios:asignar'),
    _NavItem('Usuarios pendientes', Icons.how_to_reg_outlined, '/modulos/usuarios-pendientes', 'usuarios:asignar'),
    _NavItem('Configuración', Icons.settings_outlined, '/modulos/configuracion', 'configuracion:ver'),
  ];

  static String _roleLabel(UserProfile profile) {
    if (profile.roles.isEmpty) return 'Usuario';
    return switch (profile.roles.first.toLowerCase()) {
      'admin' || 'administrator' || 'administrador' => 'Administrador',
      'super_admin' || 'superadmin' => 'Superadministrador',
      'technician' || 'tecnico' || 'técnico' => 'Técnico',
      'requester' || 'solicitante' => 'Solicitante',
      final value => value.replaceAll('_', ' '),
    };
  }

  bool _isSelected(_NavItem item) =>
      item.path == selectedPath ||
      // El dashboard propio y el global son el mismo elemento del menú.
      (item.path == HomeDestination.globalDashboard.path && selectedPath == HomeDestination.ownDashboard.path);

  @override
  Widget build(BuildContext context) {
    final allowed = _navItems.where((item) =>
      (item.permission == null && item.anyPermissions.isEmpty) ||
      (item.permission != null && profile.can(item.permission!)) ||
      item.anyPermissions.any(profile.can),
    ).toList();
    final homePath = resolveHome(profile.permissions).path;
    return Drawer(
      width: 306,
      backgroundColor: const Color(0xFF0B2341),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B1F3A), Color(0xFF12365C)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 16, 20),
                child: Row(
                  children: [
                    const Expanded(child: Align(alignment: Alignment.centerLeft, child: BrandLogo(asset: BrandLogo.wordmarkAsset, height: 28))),
                    IconButton(
                      tooltip: 'Cerrar menú',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  children: [
                    for (final item in allowed)
                      _DrawerItem(
                        item: item,
                        selected: _isSelected(item),
                        onTap: () {
                          Navigator.of(context).pop();
                          final target = item.label == 'Dashboard' ? homePath : item.path;
                          context.go(target);
                        },
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 8, bottom: 8),
                      child: Text('PERFIL', style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                    ),
                    Material(
                      color: const Color(0xFF24476B),
                      borderRadius: BorderRadius.circular(15),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(15),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go('/perfil');
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(11),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: AppColors.sky,
                                child: Text(initialsOf(profile.fullName), style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800)),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(profile.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                                    Text(_roleLabel(profile), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => context.read<AuthBloc>().add(const AuthSignOutRequested()),
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('Cerrar sesión'),
                      style: TextButton.styleFrom(foregroundColor: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({required this.item, required this.selected, required this.onTap});
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Material(
      color: selected ? const Color(0xFF2878AA) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 48,
          child: Row(children: [
            const SizedBox(width: 15),
            Icon(item.icon, color: Colors.white.withValues(alpha: selected ? 1 : 0.82), size: 21),
            const SizedBox(width: 14),
            Expanded(child: Text(item.label, style: TextStyle(color: Colors.white.withValues(alpha: selected ? 1 : 0.88), fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500))),
          ]),
        ),
      ),
    ),
  );
}
