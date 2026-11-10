import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

/// Tamaños de página que ofrece el selector.
const List<int> pageSizeOptions = [5, 10, 20, 50];

/// Texto «1-5 de 23» para la página [page] de tamaño [pageSize] con [shown] elementos.
String pageRangeLabel({required int page, required int pageSize, required int shown, required int total}) {
  if (total == 0 || shown == 0) return '0 de $total';
  final from = (page - 1) * pageSize + 1;
  return '$from-${from + shown - 1} de $total';
}

/// Qué se dibuja en la píldora: números de página y `null` por cada «…». Con [slots] huecos
/// (mínimo 5): todas las páginas si caben; cerca del principio «1 2 3 4 5 … 99»; en el
/// medio «1 … 4 5 6 … 99»; cerca del final «1 … 95 96 97 98 99». Primera y última siempre salen.
List<int?> visiblePages({required int page, required int totalPages, required int slots}) {
  final room = slots < 5 ? 5 : slots;
  if (totalPages <= room) return [for (var i = 1; i <= totalPages; i++) i];
  // Páginas seguidas que se muestran junto a un extremo: dejan sitio al «…» y a la otra punta.
  final edge = room - 2;
  if (page <= edge) return [for (var i = 1; i <= edge; i++) i, null, totalPages];
  if (page > totalPages - edge) return [1, null, for (var i = totalPages - edge + 1; i <= totalPages; i++) i];
  // En el medio: la actual con una vecina a cada lado, y si sobra sitio, más vecinas.
  // El tramo del medio es impar (la actual y las mismas vecinas a cada lado).
  final middle = room - 4;
  final around = ((middle.isEven ? middle - 1 : middle) - 1) ~/ 2;
  return [1, null, for (var i = page - around; i <= page + around; i++) i, null, totalPages];
}

/// Paginador: una píldora de ancho completo con flechas en los extremos y los números de
/// página en medio (la actual, en un círculo mostaza), y debajo «1-5 de 23» y el selector de
/// tamaño de página.
///
/// * Con una sola página la píldora muestra solo «1», sin flechas.
/// * En la primera página no hay «anterior»; en la última, no hay «siguiente».
/// * El selector de tamaño solo aparece si el total supera la opción más pequeña
///   y la pantalla pasa [onPageSize].
class Paginator extends StatelessWidget {
  const Paginator({
    super.key,
    required this.page,
    required this.pageSize,
    required this.shown,
    required this.total,
    required this.totalPages,
    required this.onPage,
    this.onPageSize,
    this.loading = false,
  });

  /// Página actual, base 1.
  final int page;
  final int pageSize;

  /// Elementos de la página actual.
  final int shown;
  final int total;
  final int totalPages;
  final ValueChanged<int> onPage;

  /// Se llama con el tamaño elegido; la pantalla vuelve a la página 1.
  final ValueChanged<int>? onPageSize;
  final bool loading;

  /// Ancho de cada número de página y lado de cada flecha (48: el mínimo táctil de Material).
  static const _cell = 34.0;
  static const _arrow = 48.0;

  @override
  Widget build(BuildContext context) {
    if (total <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final showSize = onPageSize != null && total > pageSizeOptions.first;
    final sizes = {...pageSizeOptions, pageSize}.toList()..sort();
    final label = theme.textTheme.labelLarge?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w700);

    void go(int value) {
      if (!loading) onPage(value);
    }

    return Opacity(
      opacity: loading ? .5 : 1,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // La píldora sale siempre; con una sola página muestra «1» y ninguna flecha.
        _Pill(page: page, totalPages: totalPages < 1 ? 1 : totalPages, onPage: go),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: AppSpacing.xs,
          spacing: AppSpacing.md,
          children: [
            Text(pageRangeLabel(page: page, pageSize: pageSize, shown: shown, total: total), style: label),
            if (showSize)
              Semantics(
                label: 'Elementos por página',
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: sizes.contains(pageSize) ? pageSize : null,
                    isDense: false,
                    borderRadius: AppRadius.mdAll,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.slate),
                    style: label,
                    items: [for (final size in sizes) DropdownMenuItem(value: size, child: Text('$size por página'))],
                    onChanged: loading ? null : (value) => value == null || value == pageSize ? null : onPageSize!(value),
                  ),
                ),
              ),
          ],
        ),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.page, required this.totalPages, required this.onPage});

  final int page;
  final int totalPages;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          // Cuántos números caben entre las dos flechas; en pantallas estrechas, menos.
          // (Menos el relleno y el borde de la píldora.)
          final room = ((constraints.maxWidth - 2 * Paginator._arrow - 2 * AppSpacing.sm - 2) / Paginator._cell).floor();
          final pages = visiblePages(page: page, totalPages: totalPages, slots: room.clamp(5, 7));
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              // Píldora en un mostaza muy suave; la página actual va en mostaza pleno.
              color: Color.alphaBlend(AppColors.mustard.withValues(alpha: .16), AppColors.white),
              borderRadius: AppRadius.pillAll,
              border: Border.all(color: AppColors.mustard.withValues(alpha: .35)),
              boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: .10), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              if (page > 1)
                IconButton(
                  tooltip: 'Página anterior',
                  constraints: const BoxConstraints.tightFor(width: Paginator._arrow, height: Paginator._arrow),
                  padding: EdgeInsets.zero,
                  color: AppColors.steel,
                  onPressed: () => onPage(page - 1),
                  icon: const Icon(Icons.chevron_left_rounded),
                )
              else
                const SizedBox(width: Paginator._arrow, height: Paginator._arrow),
              // Si por el tamaño de letra no caben, los números se encogen en vez de desbordar.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final number in pages)
                      if (number == null) const _Ellipsis() else _PageNumber(number: number, selected: number == page, onTap: () => onPage(number)),
                  ]),
                ),
              ),
              if (page < totalPages)
                IconButton(
                  tooltip: 'Página siguiente',
                  constraints: const BoxConstraints.tightFor(width: Paginator._arrow, height: Paginator._arrow),
                  padding: EdgeInsets.zero,
                  color: AppColors.steel,
                  onPressed: () => onPage(page + 1),
                  icon: const Icon(Icons.chevron_right_rounded),
                )
              else
                const SizedBox(width: Paginator._arrow, height: Paginator._arrow),
            ]),
          );
        },
      );
}

class _PageNumber extends StatelessWidget {
  const _PageNumber({required this.number, required this.selected, required this.onTap});

  final int number;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: 'Página $number',
        excludeSemantics: true,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: selected ? null : onTap,
          child: SizedBox(
            width: Paginator._cell,
            height: Paginator._arrow,
            child: Center(
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                // La página actual: círculo mostaza con un aro más claro alrededor.
                decoration: BoxDecoration(
                  color: selected ? AppColors.mustard : Colors.transparent,
                  shape: BoxShape.circle,
                  boxShadow: selected ? [BoxShadow(color: AppColors.mustard.withValues(alpha: .35), spreadRadius: 3)] : null,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('$number', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: selected ? AppColors.navy : AppColors.steel, fontWeight: selected ? FontWeight.w900 : FontWeight.w600)),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Los puntos suspensivos entre dos tramos de páginas: no se pueden tocar.
class _Ellipsis extends StatelessWidget {
  const _Ellipsis();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          width: Paginator._cell - 8,
          height: Paginator._arrow,
          child: Center(child: Text('…', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.slate, fontWeight: FontWeight.w700))),
        ),
      );
}
