import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

/// Fracción máxima de la altura que ocupa una hoja: deja ver el encabezado de la pantalla.
const double mantixSheetMaxHeight = .9;

/// Hoja inferior arrastrable (patrón de los detalles y formularios).
///
/// Ocupa hasta el 90 % de la altura, con asa, título y botón de cerrar. [builder] recibe el
/// `ScrollController` de la hoja: debe dárselo a su lista para que arrastrar y desplazar
/// funcionen juntos. El contenido sube con el teclado.
Future<T?> showMantixSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext context, ScrollController controller) builder,
  Widget? footer,
  double initialHeight = mantixSheetMaxHeight,
}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _MantixSheet(title: title, builder: builder, footer: footer, initialHeight: initialHeight),
    );

class _MantixSheet extends StatelessWidget {
  const _MantixSheet({required this.title, required this.builder, required this.footer, required this.initialHeight});

  final String title;
  final Widget Function(BuildContext context, ScrollController controller) builder;
  final Widget? footer;
  final double initialHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: initialHeight,
      minChildSize: .5,
      maxChildSize: mantixSheetMaxHeight,
      builder: (context, controller) => Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg + 8)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: Column(children: [
            const SizedBox(height: AppSpacing.sm),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.grey, borderRadius: AppRadius.pillAll)),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.xs, 0),
              child: Row(children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)),
                  ),
                ),
                IconButton(tooltip: 'Cerrar', onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            const Divider(height: 1),
            Expanded(child: builder(context, controller)),
            if (footer != null) SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(AppSpacing.md), child: footer)),
          ]),
        ),
      ),
    );
  }
}
