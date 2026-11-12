import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

/// Encabezado azul de la pantalla de técnicos, a todo el ancho: el banner de fondo (con su
/// ilustración a la derecha), el título y la explicación. [action] es el botón del encabezado
/// (por ejemplo «Registrar técnico») y solo se pasa a quien puede usarlo.
class TechniciansHeader extends StatelessWidget {
  const TechniciansHeader({super.key, this.action});

  static const asset = 'assets/images/tecnicos.png';

  /// Ancho que se deja libre a la derecha para la ilustración del banner.
  static const _illustrationWidth = 92.0;

  final Widget? action;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
        child: Stack(children: [
          // El banner cubre todo el encabezado; si falta, queda el degradado de la marca.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.bannerDeep, AppColors.bannerLight])),
              child: Image(image: AssetImage(asset), fit: BoxFit.cover, alignment: Alignment.centerRight, excludeFromSemantics: true, errorBuilder: _noImage),
            ),
          ),
          // Oscurece la zona del texto: las franjas claras del banner no le quitan contraste.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.navy.withValues(alpha: .82), AppColors.navy.withValues(alpha: .55), AppColors.navy.withValues(alpha: 0)], stops: const [0, .6, .85]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(right: _illustrationWidth),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'PERSONAL ', style: TextStyle(color: AppColors.white)),
                    TextSpan(text: 'TÉCNICO', style: TextStyle(color: AppColors.mustard)),
                    TextSpan(text: ' Y ESPECIALISTAS', style: TextStyle(color: AppColors.white)),
                  ]),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: 0.2),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Padding(
                padding: EdgeInsets.only(right: _illustrationWidth),
                child: Text(
                  'Supervisa al equipo técnico: disponibilidad, especialidades y carga de tickets.',
                  style: TextStyle(color: AppColors.skyLight, fontSize: 12.5, height: 1.35),
                ),
              ),
              if (action != null) ...[const SizedBox(height: AppSpacing.md), action!],
            ]),
          ),
        ]),
      );

  static Widget _noImage(BuildContext context, Object error, StackTrace? stackTrace) => const SizedBox.shrink();
}
