import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../bloc/notifications/notifications_bloc.dart';
import '../../core/routing/home_resolver.dart';
import '../../core/theme/app_colors.dart';
import '../../models/auth/user_profile.dart';
import 'brand_logo.dart';
import 'mantix_drawer.dart';
import 'notifications_sheet.dart';

/// Encabezado de todos los módulos: la «M» a la izquierda, junto al botón del menú; la campana
/// de notificaciones (con un punto si hay sin leer, abre el panel) y el avatar (abre el perfil).
class MantixAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MantixAppBar({super.key, required this.profile});

  final UserProfile profile;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final unread = context.select((NotificationsBloc bloc) => bloc.state.unreadCount);
    return AppBar(
      backgroundColor: const Color(0xFF071D35),
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 0,
      title: const BrandLogo(asset: BrandLogo.markAsset, height: 26),
      actions: [
        IconButton(
          tooltip: unread > 0 ? 'Notificaciones, $unread sin leer' : 'Notificaciones',
          onPressed: () => showNotificationsSheet(context),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_none_rounded, size: 25),
              if (unread > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(color: AppColors.mustard, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 10, left: 2),
          child: Tooltip(
            message: 'Perfil',
            child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => context.go(HomeDestination.profile.path),
            child: Padding(
              padding: const EdgeInsets.all(6),
              // Solo la burbuja con las iniciales: sin la flecha, que no abre ningún menú (lleva al perfil).
              child: MyAvatar(name: profile.fullName, radius: 16, fontSize: 11),
            ),
          ),
          ),
        ),
      ],
    );
  }
}
