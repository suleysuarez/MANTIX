import 'package:flutter/material.dart';

import '../../core/format/users_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/users/user_models.dart';
import '../home/mantix_drawer.dart' show initialsOf;
import '../shared/app_chip.dart';
import 'users_tones.dart';

/// El icono de un rol según su código (solo decora: nunca decide qué puede hacer alguien). Un rol
/// que la app no conoce usa el escudo genérico.
IconData roleIcon(String code) => switch (code.toUpperCase()) {
      'ADMIN' => Icons.settings_rounded,
      'SUPERVISOR' => Icons.verified_user_outlined,
      'TECHNICIAN' => Icons.build_rounded,
      'EMPLOYEE' => Icons.person_add_alt_1_outlined,
      'AUDITOR' => Icons.description_outlined,
      _ => Icons.admin_panel_settings_outlined,
    };

/// Círculo con las iniciales de la persona; apagado si la cuenta está inactiva.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.muted = false, this.size = 42});

  final String name;
  final bool muted;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: (muted ? AppColors.grey : AppColors.skyLight).withValues(alpha: .5), shape: BoxShape.circle),
          child: Text(initialsOf(name), style: TextStyle(color: muted ? AppColors.slate : AppColors.steel, fontWeight: FontWeight.w900, fontSize: size * .36)),
        ),
      );
}

/// Pastilla con el nombre de un rol y, si se pasa, su [icon].
class RoleChip extends StatelessWidget {
  const RoleChip(this.label, {super.key, this.tone, this.icon});

  final String label;
  final ChipColors? tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = tone ?? skyTone;
    return Container(
      constraints: const BoxConstraints(maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: colors.background, borderRadius: AppRadius.pillAll),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: colors.foreground), const SizedBox(width: 4)],
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.foreground, fontWeight: FontWeight.w800))),
      ]),
    );
  }
}

/// Una persona en la lista de usuarios: nombre, correo, sus roles y, a la derecha, el estado de la
/// cuenta. El último acceso y lo demás están en su ficha.
class UserCard extends StatelessWidget {
  const UserCard({super.key, required this.user, required this.now, this.onTap});

  final ManagedUser user;

  /// Hora con la que se calcula el estado de la cuenta (se inyecta para poder probarla).
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = accessState(isActive: user.isActive, lastLoginAt: user.lastLoginAt);
    return Material(
      color: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll, side: BorderSide(color: AppColors.skyLight.withValues(alpha: .8))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            UserAvatar(name: user.fullName, muted: !user.isActive, size: 46),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user.fullName, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800, height: 1.2)),
                const SizedBox(height: 2),
                Text(user.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel)),
                const SizedBox(height: AppSpacing.sm),
                // Los roles a la izquierda y el estado a la derecha; si no caben, se acomodan en
                // varias líneas en vez de desbordarse con letra grande en una pantalla estrecha.
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      if (user.roles.isEmpty) RoleChip('Sin rol', tone: mustardTone, icon: Icons.person_off_outlined) else for (final role in user.roles) RoleChip(role.name, icon: roleIcon(role.code)),
                    ]),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(child: AppChip(label: accessLabel(state), colors: accessColors(state), semanticPrefix: 'Estado')),
                ]),
              ]),
            ),
            if (onTap != null) const Padding(padding: EdgeInsets.only(top: 12, left: 4), child: Icon(Icons.chevron_right_rounded, color: AppColors.steel)),
          ]),
        ),
      ),
    );
  }
}

/// Una persona de la pestaña Pendientes: ya entró pero aún no tiene rol. [action] (por ejemplo
/// «Asignar rol») va debajo de la tarjeta; `null` si no hay acción.
class PendingUserCard extends StatelessWidget {
  const PendingUserCard({super.key, required this.user, this.action});

  final PendingUser user;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.lgAll, border: Border.all(color: AppColors.skyLight.withValues(alpha: .8))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          UserAvatar(name: user.fullName, size: 46),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user.fullName, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800, height: 1.2)),
              const SizedBox(height: 2),
              Text(user.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel)),
              const SizedBox(height: AppSpacing.sm),
              AppChip(label: 'Pendiente de asignación', colors: mustardTone, semanticPrefix: 'Estado'),
            ]),
          ),
        ]),
      ),
      if (action != null) ...[const SizedBox(height: AppSpacing.sm), action!],
    ]);
  }
}

/// Un rol de la pestaña Roles: su icono, su nombre, qué es (si se sabe) y, a la derecha, cuántas
/// personas lo tienen.
class RoleCard extends StatelessWidget {
  const RoleCard({super.key, required this.role});

  final RoleInfo role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = role.userCount;
    final description = role.description?.trim() ?? '';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.lgAll, border: Border.all(color: AppColors.skyLight.withValues(alpha: .8))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .5), borderRadius: BorderRadius.circular(14)),
          child: Icon(roleIcon(role.code), size: 24, color: AppColors.steel),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(role.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800, height: 1.2))),
              if (count != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Semantics(
                  label: count == 1 ? '1 persona' : '$count personas',
                  excludeSemantics: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: skyTone.background, borderRadius: AppRadius.pillAll),
                    child: Text(count == 1 ? '1 persona' : '$count personas', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ]),
            if (description.isNotEmpty) ...[const SizedBox(height: 4), Text(description, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel, height: 1.3))],
            if (!role.isActive) ...[const SizedBox(height: AppSpacing.sm), RoleChip('Inactivo', tone: greyTone)],
          ]),
        ),
      ]),
    );
  }
}
