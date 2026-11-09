import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/home_resolver.dart';
import '../../core/theme/app_colors.dart';
import '../../models/auth/user_profile.dart';
import 'brand_logo.dart';
import 'mantix_drawer.dart';

/// Encabezado de las pantallas con menú: la «M» a la izquierda, junto al botón del menú,
/// y el avatar (abre el perfil). La campana solo aparece si la pantalla pasa [onAlertsPressed].
class MantixAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MantixAppBar({super.key, required this.profile, this.hasAlerts = false, this.onAlertsPressed});

  final UserProfile profile;

  /// Muestra un punto sobre la campana.
  final bool hasAlerts;
  final VoidCallback? onAlertsPressed;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
    backgroundColor: const Color(0xFF071D35),
    foregroundColor: Colors.white,
    elevation: 0,
    centerTitle: false,
    titleSpacing: 0,
    title: const BrandLogo(asset: BrandLogo.markAsset, height: 26),
    actions: [
      if (onAlertsPressed != null)
        IconButton(
          tooltip: 'Ver alertas',
          onPressed: onAlertsPressed,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_none_rounded, size: 25),
              if (hasAlerts)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: AppColors.mustard, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(right: 10, left: 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => context.go(HomeDestination.profile.path),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.sky,
                child: Text(initialsOf(profile.fullName), style: const TextStyle(color: AppColors.navy, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
            ]),
          ),
        ),
      ),
    ],
  );
}
