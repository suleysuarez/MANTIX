import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../core/routing/home_resolver.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/home/mantix_app_bar.dart';
import '../../widgets/home/mantix_drawer.dart';

class ModulePlaceholderScreen extends StatelessWidget {
  const ModulePlaceholderScreen({super.key, required this.module});

  final String module;

  static const _titles = <String, String>{
    'equipos': 'Equipos',
    'tickets': 'Tickets',
    'tecnicos': 'Técnicos',
    'mantenimiento': 'Mantenimiento',
    'inventario': 'Inventario',
    'usuarios': 'Usuarios',
    'roles': 'Roles y permisos',
    'usuarios-pendientes': 'Usuarios pendientes',
    'configuracion': 'Configuración',
  };

  @override
  Widget build(BuildContext context) {
    final title = _titles[module] ?? 'Módulo';
    final auth = context.watch<AuthBloc>().state;
    final profile = auth is Authenticated ? auth.profile : null;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F7FC),
      appBar: profile == null ? AppBar(title: Text(title)) : MantixAppBar(profile: profile),
      drawer: profile == null ? null : MantixDrawer(profile: profile, selectedPath: '/modulos/$module'),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(color: AppColors.sky.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(24)),
                child: const Icon(Icons.construction_rounded, color: AppColors.steel, size: 38),
              ),
              const SizedBox(height: 18),
              Text(title, style: const TextStyle(color: Color(0xFF0B1F3A), fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text(
                'Este módulo se integrará en la siguiente fase de la app móvil. El acceso ya respeta tus permisos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.slate, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 18),
              if (profile != null)
                FilledButton.icon(
                  onPressed: () => context.go(resolveHome(profile.permissions).path),
                  icon: const Icon(Icons.home_rounded),
                  label: const Text('Ir al inicio'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
