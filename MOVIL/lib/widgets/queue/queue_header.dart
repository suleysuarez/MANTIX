import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

/// Encabezado azul de la bandeja de triaje, a todo el ancho de la pantalla: título, explicación
/// e ilustración.
class QueueHeader extends StatelessWidget {
  const QueueHeader({super.key});

  static const asset = 'assets/images/solicitudes.png';
  static const _illustrationWidth = 120.0;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.bannerDeep, AppColors.bannerLight]),
          ),
          child: Stack(children: [
            // Solo la zona de la bandeja del archivo (sin sus márgenes blancos); el borde izquierdo
            // se funde con el degradado.
            const Positioned(right: 0, bottom: 0, width: _illustrationWidth, height: 96, child: _Illustration()),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'SOLICITUDES\n', style: TextStyle(color: AppColors.white)),
                    TextSpan(text: 'PENDIENTES', style: TextStyle(color: AppColors.mustard)),
                  ]),
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: 0.2),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Padding(
                  padding: EdgeInsets.only(right: _illustrationWidth - 24),
                  child: Text(
                    'Clasifica, asigna o rechaza lo que espera trabajo. Arrastra una tarjeta a otra columna para cambiar su estado.',
                    style: TextStyle(color: AppColors.skyLight, fontSize: 12.5, height: 1.35),
                  ),
                ),
                // Deja sitio a la ilustración cuando el texto es corto.
                const SizedBox(height: AppSpacing.xl),
              ]),
            ),
          ]),
        ),
      );
}

class _Illustration extends StatelessWidget {
  const _Illustration();

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(colors: [Colors.transparent, Colors.black], stops: [0, 0.35]).createShader(rect),
        child: ClipRect(
          // Zona 1300–2170 × 100–615 del archivo de 2170 × 725.
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: Alignment.bottomRight,
            child: ClipRect(
              child: Align(
                alignment: const Alignment(1, 0),
                widthFactor: 870 / 2170,
                heightFactor: 515 / 725,
                child: Image.asset(asset, width: 2170, height: 725, fit: BoxFit.fill, semanticLabel: '', excludeFromSemantics: true),
              ),
            ),
          ),
        ),
      );

  static const asset = QueueHeader.asset;
}
