import 'package:flutter/painting.dart';

import '../../core/format/users_format.dart';
import '../../core/theme/app_colors.dart';

/// Colores de la pantalla de usuarios, todos de la paleta de la marca: lo normal en azul claro y
/// acero, lo que espera algo (primer ingreso, sin rol) en mostaza suave y lo apagado en gris.
/// Texto contra fondo con contraste AA.
ChipColors get skyTone => ChipColors(background: Color.alphaBlend(AppColors.skyLight.withValues(alpha: .55), AppColors.white), foreground: AppColors.navy, dot: AppColors.steel);

ChipColors get mustardTone => ChipColors(background: Color.alphaBlend(AppColors.mustard.withValues(alpha: .38), AppColors.white), foreground: AppColors.navy, dot: AppColors.mustard);

ChipColors get greyTone => ChipColors(background: Color.alphaBlend(AppColors.grey.withValues(alpha: .45), AppColors.white), foreground: AppColors.steel, dot: AppColors.slate);

/// Chip del estado de una cuenta.
ChipColors accessColors(AccessState state) => switch (state) {
      AccessState.active => skyTone,
      AccessState.inactive => greyTone,
      AccessState.never => mustardTone,
    };
