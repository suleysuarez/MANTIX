import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../shared/status_message.dart';

/// Cuenta con roles pero sin ningún permiso: distinta de la cuenta pendiente.
class NoAccessScreen extends ConsumerWidget {
  const NoAccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(sessionProvider.notifier);
    return StatusMessage(
      icon: Icons.block,
      title: 'Sin acceso asignado',
      message: 'Tu cuenta tiene un rol, pero todavía no incluye permisos para usar la app. Pide a un administrador que lo revise.',
      actions: [
        FilledButton(onPressed: controller.refresh, child: const Text('Volver a comprobar')),
        OutlinedButton(onPressed: controller.signOut, child: const Text('Cerrar sesión')),
      ],
    );
  }
}
