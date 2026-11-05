import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/glass_card.dart';
import '../../../shared/status_message.dart';
import 'widgets/auth_shell.dart';

/// Pantalla de acceso. Con Clerk iniciado muestra su formulario de inicio de
/// sesión sobre la imagen de la marca, dentro de una tarjeta de vidrio; sin él
/// (sin clave o sin red al arrancar) lo dice con claridad.
///
/// El formulario de Clerk viene del SDK y hoy solo trae textos en inglés.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, required this.hasClerk});

  /// `false` si Clerk no arrancó (sin clave o sin red).
  final bool hasClerk;

  @override
  Widget build(BuildContext context) {
    if (!hasClerk) {
      return const StatusMessage(
        icon: Icons.lock_outline,
        title: 'Inicio de sesión no disponible',
        message:
            'No se pudo iniciar el servicio de acceso. Revisa que la app tenga CLERK_PUBLISHABLE_KEY y conexión a internet, y ábrela de nuevo.',
      );
    }

    return AuthShell(
      child: GlassCard(
        child: Theme(
          data: AppTheme.authGlass(Theme.of(context)),
          child: const ClerkAuthentication(),
        ),
      ),
    );
  }
}