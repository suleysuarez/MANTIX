import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/home_resolver.dart';
import '../../../core/auth/session.dart';
import '../../../shared/status_message.dart';
import '../../dev/presentation/components_gallery_screen.dart';

/// Marcador de cada pantalla de inicio hasta que se construyan en las fases 4 a 7.
/// Mientras tanto ofrece cerrar sesión y, en debug, la galería de componentes.
class HomePlaceholderScreen extends ConsumerWidget {
  const HomePlaceholderScreen({super.key, required this.destination});

  final HomeDestination destination;

  static String titleOf(HomeDestination destination) => switch (destination) {
        HomeDestination.globalDashboard => 'Dashboard global',
        HomeDestination.assignedInbox => 'Mi bandeja de trabajo',
        HomeDestination.myRequests => 'Mis solicitudes',
        HomeDestination.reports => 'Reportes',
        HomeDestination.ownDashboard => 'Mi dashboard',
        HomeDestination.profile => 'Perfil',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StatusMessage(
      icon: Icons.construction,
      title: titleOf(destination),
      message: 'Esta pantalla se construye en una fase posterior.',
      actions: [
        if (kDebugMode)
          OutlinedButton.icon(
            onPressed: () => context.push(ComponentsGalleryScreen.path),
            icon: const Icon(Icons.widgets_outlined),
            label: const Text('Galería de componentes'),
          ),
        TextButton(onPressed: ref.read(sessionProvider.notifier).signOut, child: const Text('Cerrar sesión')),
      ],
    );
  }
}
