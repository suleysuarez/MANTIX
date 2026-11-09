import 'package:flutter/material.dart';

/// Logo de Mantix. Solo la «M» (encabezado) y el logo completo recortado (panel lateral);
/// ambos salen de `mantix_logo.webp` sin el espacio transparente que sobra.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, required this.asset, this.height = 22});

  static const markAsset = 'assets/images/mantix_m.webp';
  static const wordmarkAsset = 'assets/images/mantix_wordmark.webp';

  final String asset;
  final double height;

  @override
  Widget build(BuildContext context) => Image.asset(
    asset,
    height: height,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
    semanticLabel: 'MANTIX',
  );
}
