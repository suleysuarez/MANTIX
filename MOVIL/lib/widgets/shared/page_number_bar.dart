import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Páginas que se muestran como botones: la primera, la última y las vecinas de la actual
/// (`null` marca un hueco).
List<int?> pageButtons(int page, int totalPages) {
  final shown = <int>{1, totalPages, page - 1, page, page + 1}.where((p) => p >= 1 && p <= totalPages).toList()..sort();
  final result = <int?>[];
  for (var i = 0; i < shown.length; i++) {
    if (i > 0 && shown[i] - shown[i - 1] > 1) result.add(null);
    result.add(shown[i]);
  }
  return result;
}

/// Botones de página: anterior, números con huecos y siguiente. Con [loading] se atenúan
/// mientras llega la página pedida.
class PageNumberBar extends StatelessWidget {
  const PageNumberBar({super.key, required this.page, required this.totalPages, required this.onPage, this.loading = false, this.selectedColor = AppColors.steel});

  final int page;
  final int totalPages;
  final ValueChanged<int> onPage;
  final bool loading;
  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();
    void go(int value) {
      if (!loading) onPage(value);
    }

    return Opacity(
      opacity: loading ? .5 : 1,
      child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
        _PageButton(icon: Icons.chevron_left_rounded, tooltip: 'Página anterior', selectedColor: selectedColor, onTap: page > 1 ? () => go(page - 1) : null),
        for (final number in pageButtons(page, totalPages))
          if (number == null)
            const SizedBox(width: 28, child: Center(child: Text('…', style: TextStyle(color: AppColors.slate))))
          else
            _PageButton(label: '$number', selected: number == page, tooltip: 'Página $number', selectedColor: selectedColor, onTap: number == page ? null : () => go(number)),
        _PageButton(icon: Icons.chevron_right_rounded, tooltip: 'Página siguiente', selectedColor: selectedColor, onTap: page < totalPages ? () => go(page + 1) : null),
      ]),
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({this.label, this.icon, required this.tooltip, required this.selectedColor, this.selected = false, this.onTap});

  final Color selectedColor;

  final String? label;
  final IconData? icon;
  final String tooltip;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(
        button: true,
        selected: selected,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? selectedColor : Colors.transparent),
            child: label != null
                ? Text(label!, style: TextStyle(color: selected ? Colors.white : AppColors.steel, fontSize: 13, fontWeight: FontWeight.w800))
                : Icon(icon, size: 22, color: onTap == null ? AppColors.grey : AppColors.steel),
          ),
        ),
        ),
      );
}

