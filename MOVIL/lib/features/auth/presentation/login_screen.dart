import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/clerk_auth_provider.dart';
import '../../../shared/status_message.dart';

/// Pantalla de acceso. Con Clerk iniciado muestra su formulario de inicio de
/// sesión; sin él (sin clave o sin red al arrancar) lo dice con claridad.
///
/// El formulario de Clerk viene del SDK y hoy solo trae textos en inglés.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(clerkAuthStateProvider) == null) {
      return const StatusMessage(
        icon: Icons.lock_outline,
        title: 'Inicio de sesión no disponible',
        message:
            'No se pudo iniciar el servicio de acceso. Revisa que la app tenga CLERK_PUBLISHABLE_KEY y conexión a internet, y ábrela de nuevo.',
      );
    }
    return const Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: ClerkAuthentication(),
        ),
      ),
    );
  }
}
