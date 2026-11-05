import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/auth/bloc/auth_bloc.dart';
import '../../../shared/status_message.dart';

/// Cuenta autenticada sin ningún rol: espera aprobación de un administrador.
class PendingScreen extends StatelessWidget {
  const PendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<AuthBloc>();
    return StatusMessage(
      icon: Icons.hourglass_top,
      title: 'Cuenta pendiente de aprobación',
      message: 'Un administrador debe asignarte un rol antes de que puedas usar Mantix. Te avisaremos cuando esté listo.',
      actions: [
        FilledButton(onPressed: () => bloc.add(const AuthRefreshRequested()), child: const Text('Volver a comprobar')),
        OutlinedButton(onPressed: () => bloc.add(const AuthSignOutRequested()), child: const Text('Cerrar sesión')),
      ],
    );
  }
}
