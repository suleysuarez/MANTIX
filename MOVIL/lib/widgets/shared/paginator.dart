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

/// Paginador: «1-5 de 23», flechas y selector de tamaño de página.
///
/// * Con una sola página no hay flechas ni «1 de 1».
/// * En la primera página no hay botón «anterior»; en la última, no hay «siguiente».
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

  @override
  Widget build(BuildContext context) {
    if (total <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final multiple = totalPages > 1;
    final showSize = onPageSize != null && total > pageSizeOptions.first;
    final sizes = {...pageSizeOptions, pageSize}.toList()..sort();
    final label = theme.textTheme.labelLarge?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w700);

    void go(int value) {
      if (!loading) onPage(value);
    }

    return Opacity(
      opacity: loading ? .5 : 1,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
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
          if (multiple)
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (page > 1)
                IconButton(tooltip: 'Página anterior', onPressed: () => go(page - 1), icon: const Icon(Icons.chevron_left_rounded))
              else
                const SizedBox(width: 48, height: 48),
              Text('$page / $totalPages', style: label),
              if (page < totalPages)
                IconButton(tooltip: 'Página siguiente', onPressed: () => go(page + 1), icon: const Icon(Icons.chevron_right_rounded))
              else
                const SizedBox(width: 48, height: 48),
            ]),
        ],
      ),
    );
  }
}
