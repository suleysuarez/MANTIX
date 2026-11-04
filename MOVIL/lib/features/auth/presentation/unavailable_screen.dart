import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../shared/status_message.dart';

/// Hay sesión pero no se pudo cargar el perfil (red o servidor). Se puede reintentar.
class UnavailableScreen extends ConsumerWidget {
  const UnavailableScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionProvider).value;
    final message = state is SessionUnavailable ? state.failure.message : 'No pudimos cargar tu perfil.';
    return StatusMessage(
      icon: Icons.cloud_off,
      title: 'No pudimos conectar',
      message: message,
      actions: [
        FilledButton(onPressed: ref.read(sessionProvider.notifier).refresh, child: const Text('Reintentar')),
      ],
    );
  }
}
