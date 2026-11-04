import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_tokens.dart';

/// Tarjeta translúcida con desenfoque. **Solo para elementos puntuales** (el plan
/// no admite glass en toda la interfaz). Se coloca sobre un fondo oscuro o de
/// color y con texto blanco: sobre fondo claro no hay contraste suficiente.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(AppSpacing.lg)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.lgAll,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.25),
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: AppColors.white.withValues(alpha: 0.5)),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
