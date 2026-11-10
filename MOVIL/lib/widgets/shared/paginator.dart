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

/// Números de página que caben: una ventana de [maxVisible] consecutivas que sigue a la actual.
List<int> visiblePages({required int page, required int totalPages, required int maxVisible}) {
  if (totalPages <= maxVisible) return [for (var i = 1; i <= totalPages; i++) i];
  final start = (page - maxVisible ~/ 2).clamp(1, totalPages - maxVisible + 1);
  return [for (var i = start; i < start + maxVisible; i++) i];
}

/// Paginador: una píldora de ancho completo con flechas en los extremos y los números de
/// página en medio (la actual, en un círculo mostaza), y debajo «1-5 de 23» y el selector de
/// tamaño de página.
///
/// * Con una sola página no hay píldora.
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
  static const _cell = 40.0;
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
        if (totalPages > 1) _Pill(page: page, totalPages: totalPages, onPage: go),
        if (totalPages > 1) const SizedBox(height: AppSpacing.sm),
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
          final pages = visiblePages(page: page, totalPages: totalPages, maxVisible: room.clamp(3, 7));
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: AppRadius.pillAll,
              border: Border.all(color: AppColors.skyLight.withValues(alpha: .6)),
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
              Row(mainAxisSize: MainAxisSize.min, children: [for (final number in pages) _PageNumber(number: number, selected: number == page, onTap: () => onPage(number))]),
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
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: selected ? AppColors.mustard : Colors.transparent, shape: BoxShape.circle),
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
