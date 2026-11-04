import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';

/// Perfil del usuario con sus roles y permisos efectivos. También es el inicio
/// de quien no tiene ningún permiso de las demás pantallas.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionProvider).value;
    final profile = state is SignedIn ? state.profile : null;
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
                  onPressed: ref.read(sessionProvider.notifier).signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Cerrar sesión'),
                ),
              ],
            ),
    );
  }
}
