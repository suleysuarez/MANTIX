import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth/auth_bloc.dart';

/// Perfil del usuario con sus roles y permisos efectivos. También es el inicio
/// de quien no tiene ningún permiso de las demás pantallas.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // El Perfil también es el inicio de quien no tiene otros permisos; solo se muestra con sesión activa.
    final profile = context.watch<AuthBloc>().state.profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: profile == null
          ? const Center(child: CircularProgressIndicator(semanticsLabel: 'Cargando'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(profile.fullName, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text(profile.email),
                if (profile.employeeCode != null) Text('Código de empleado: ${profile.employeeCode}'),
                const SizedBox(height: 16),
                Text('Roles', style: Theme.of(context).textTheme.titleMedium),
                Wrap(spacing: 8, children: [for (final role in profile.roles) Chip(label: Text(role))]),
                const SizedBox(height: 16),
                Text('Permisos (${profile.permissions.length})', style: Theme.of(context).textTheme.titleMedium),
                Wrap(spacing: 8, children: [for (final code in profile.permissions.toList()..sort()) Chip(label: Text(code))]),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => context.read<AuthBloc>().add(const AuthSignOutRequested()),
                  icon: const Icon(Icons.logout),
                  label: const Text('Cerrar sesión'),
                ),
              ],
            ),
    );
  }
}
