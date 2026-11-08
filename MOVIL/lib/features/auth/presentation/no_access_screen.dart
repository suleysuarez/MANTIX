import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/auth/auth_bloc.dart';
import '../../../widgets/shared/status_message.dart';

/// Cuenta con roles pero sin ningún permiso: distinta de la cuenta pendiente.
class NoAccessScreen extends StatelessWidget {
  const NoAccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<AuthBloc>();
    return StatusMessage(
      icon: Icons.block,
      title: 'Sin acceso asignado',
      message: 'Tu cuenta tiene un rol, pero todavía no incluye permisos para usar la app. Pide a un administrador que lo revise.',
      actions: [
        FilledButton(onPressed: () => bloc.add(const AuthRefreshRequested()), child: const Text('Volver a comprobar')),
        OutlinedButton(onPressed: () => bloc.add(const AuthSignOutRequested()), child: const Text('Cerrar sesión')),
      ],
    );
  }
}
