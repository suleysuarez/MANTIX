import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

/// Hoja inferior que deja ver la pantalla de atrás, desenfocada, en vez de taparla.
///
/// Con [heightFactor] ocupa esa fracción de la altura (el encabezado de la pantalla sigue a la
/// vista, borroso); sin él se ajusta a su contenido. Tocar fuera la cierra. [builder] recibe el
/// contexto de la hoja: se puede cerrar con `Navigator.pop`.
///
/// La hoja cuelga del Navigator, fuera de los providers de la pantalla: si usa un Bloc, hay que
/// pasárselo con `BlocProvider.value` dentro de [builder].
Future<T?> showBlurredSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double? heightFactor,
}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      elevation: 0,
      builder: (sheetContext) => Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(sheetContext).pop(),
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: ColoredBox(color: AppColors.navy.withValues(alpha: .22)),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: heightFactor,
            widthFactor: 1,
            child: Material(
              color: AppColors.canvas,
              elevation: 8,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg + 8)),
              clipBehavior: Clip.antiAlias,
              child: Builder(builder: builder),
            ),
          ),
        ),
      ]),
    );
