import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../shared/status_message.dart';

/// Cuenta autenticada sin ningún rol: espera aprobación de un administrador.
class PendingScreen extends ConsumerWidget {
  const PendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(sessionProvider.notifier);
    return StatusMessage(
      icon: Icons.hourglass_top,
      title: 'Cuenta pendiente de aprobación',
      message: 'Un administrador debe asignarte un rol antes de que puedas usar Mantix. Te avisaremos cuando esté listo.',
      actions: [
        FilledButton(onPressed: controller.refresh, child: const Text('Volver a comprobar')),
        OutlinedButton(onPressed: controller.signOut, child: const Text('Cerrar sesión')),
      ],
    );
  }
}
