import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

/// Las tres pestañas (Usuarios, Pendientes y Roles) como píldoras: la elegida va en mostaza con
/// texto navy y las demás en blanco. «Pendientes» lleva el número de personas que esperan un rol.
/// Sigue al [controller]: tocar una píldora cambia de pestaña y deslizar el contenido mueve la
/// elegida.
class UsersTabPills extends StatelessWidget {
  const UsersTabPills({super.key, required this.controller, required this.pendingCount});

  final TabController controller;

  /// Personas que esperan un rol; con 0 la píldora no lleva número.
  final int pendingCount;

  static const _labels = ['Usuarios', 'Pendientes', 'Roles'];
  static const _icons = [Icons.groups_outlined, Icons.schedule_rounded, Icons.verified_user_outlined];

  @override
  Widget build(BuildContext context) {
    final animation = controller.animation ?? controller;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final selected = (controller.animation?.value ?? controller.index.toDouble()).round();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          child: Row(children: [
            for (var i = 0; i < _labels.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(child: _Pill(label: _labels[i], icon: _icons[i], selected: i == selected, badge: i == 1 ? pendingCount : 0, onTap: () => controller.animateTo(i))),
            ],
          ]),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.icon, required this.selected, required this.badge, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.navy : AppColors.steel;
    final text = Theme.of(context).textTheme.labelLarge?.copyWith(color: color, fontWeight: selected ? FontWeight.w800 : FontWeight.w700);
    return Semantics(
      button: true,
      selected: selected,
      label: badge > 0 ? '$label, ${badge == 1 ? '1 persona espera un rol' : '$badge personas esperan un rol'}' : label,
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.mustard : AppColors.white,
        shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.mustard : AppColors.sky)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 18, color: color),
                    const SizedBox(width: 5),
                    Text(label, maxLines: 1, style: text),
                    if (badge > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(color: selected ? AppColors.navy : AppColors.mustard, borderRadius: AppRadius.pillAll),
                        child: Text('$badge', style: TextStyle(color: selected ? AppColors.mustard : AppColors.navy, fontSize: 11, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
