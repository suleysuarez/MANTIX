import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Las dos vistas de la pantalla de reportes.
enum ReportsTab { generate, history }

/// «Generar reporte» e «Historial» como píldoras: la elegida va en navy con texto blanco.
class ReportsTabs extends StatelessWidget {
  const ReportsTabs({super.key, required this.selected, required this.onChanged});

  final ReportsTab selected;
  final ValueChanged<ReportsTab> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: 'Vista de reportes',
        child: Row(children: [
          Expanded(child: _Pill(label: 'Generar reporte', icon: Icons.bar_chart_rounded, selected: selected == ReportsTab.generate, onTap: () => onChanged(ReportsTab.generate))),
          const SizedBox(width: 8),
          Expanded(child: _Pill(label: 'Historial', icon: Icons.history_rounded, selected: selected == ReportsTab.history, onTap: () => onChanged(ReportsTab.history))),
        ]),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.white : AppColors.steel;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.navy : AppColors.white,
        shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.navy : AppColors.skyLight)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 19, color: foreground),
                  const SizedBox(width: 6),
                  Text(label, maxLines: 1, style: TextStyle(color: foreground, fontWeight: FontWeight.w800, fontSize: 14)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
