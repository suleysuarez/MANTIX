import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/auth/bloc/auth_bloc.dart';
import '../../../shared/status_message.dart';

/// Hay sesión pero no se pudo cargar el perfil (red o servidor). Se puede reintentar.
class UnavailableScreen extends StatelessWidget {
  const UnavailableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuthBloc>().state;
    final message = state is AuthUnavailable ? state.failure.message : 'No pudimos cargar tu perfil.';
    return StatusMessage(
      icon: Icons.cloud_off,
      title: 'No pudimos conectar',
      message: message,
      actions: [
        FilledButton(
          onPressed: () => context.read<AuthBloc>().add(const AuthRefreshRequested()),
          child: const Text('Reintentar'),
        ),
      ],
    );
  }
}
