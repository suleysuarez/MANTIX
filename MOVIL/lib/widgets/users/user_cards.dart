import 'package:flutter/material.dart';

import '../../core/format/users_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/users/user_models.dart';
import '../home/mantix_drawer.dart' show initialsOf;
import '../shared/app_chip.dart';
import 'users_tones.dart';

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

/// Pastilla con el nombre de un rol.
class RoleChip extends StatelessWidget {
  const RoleChip(this.label, {super.key, this.tone});

  final String label;
  final ChipColors? tone;

  @override
  Widget build(BuildContext context) {
    final colors = tone ?? skyTone;
    return Container(
      constraints: const BoxConstraints(maxWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: colors.background, borderRadius: AppRadius.pillAll),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.foreground, fontWeight: FontWeight.w800)),
    );
  }
}

/// Una persona en la lista de usuarios: nombre, correo, roles, estado de la cuenta y último acceso.
class UserCard extends StatelessWidget {
  const UserCard({super.key, required this.user, required this.now, this.onTap});

  final ManagedUser user;

  /// Hora con la que se calcula «Hace 3 h» (se inyecta para poder probarla).
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = accessState(isActive: user.isActive, lastLoginAt: user.lastLoginAt);
    return Material(
      color: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: BorderSide(color: AppColors.skyLight.withValues(alpha: .8))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            UserAvatar(name: user.fullName, muted: !user.isActive),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user.fullName, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800, height: 1.2)),
                const SizedBox(height: 2),
                Text(user.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel)),
                const SizedBox(height: AppSpacing.sm),
                // Roles y estado se acomodan en varias líneas si no caben: con letra grande en una
                // pantalla estrecha una fila fija se desbordaría.
                Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (user.roles.isEmpty) RoleChip('Sin rol', tone: mustardTone) else for (final role in user.roles) RoleChip(role.name),
                  AppChip(label: accessLabel(state), colors: accessColors(state), semanticPrefix: 'Estado'),
                ]),
                const SizedBox(height: AppSpacing.sm),
                Row(children: [
                  const Icon(Icons.schedule_rounded, size: 13, color: AppColors.slate),
                  const SizedBox(width: 4),
                  Expanded(child: Text('Último acceso: ${lastAccessText(user.lastLoginAt, now)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.slate))),
                ]),
              ]),
            ),
            if (onTap != null) const Padding(padding: EdgeInsets.only(top: 10, left: 4), child: Icon(Icons.chevron_right_rounded, color: AppColors.steel)),
          ]),
        ),
      ),
    );
  }
}

/// Una persona de la pestaña Pendientes: ya entró pero aún no tiene rol.
class PendingUserCard extends StatelessWidget {
  const PendingUserCard({super.key, required this.user, this.action});

  final PendingUser user;

  /// Lo que se puede hacer con ella (por ejemplo, «Asignar rol»); `null` si no hay acción.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.mdAll, border: Border.all(color: AppColors.skyLight.withValues(alpha: .8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          UserAvatar(name: user.fullName),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user.fullName, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800, height: 1.2)),
              const SizedBox(height: 2),
              Text(user.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel)),
              const SizedBox(height: AppSpacing.sm),
              RoleChip('Sin rol', tone: mustardTone),
            ]),
          ),
        ]),
        if (action != null) ...[const SizedBox(height: AppSpacing.sm), action!],
      ]),
    );
  }
}

/// Un rol de la pestaña Roles: nombre, código, cuántas personas lo tienen y, si se sabe, qué es.
class RoleCard extends StatelessWidget {
  const RoleCard({super.key, required this.role});

  final RoleInfo role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = role.userCount;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.mdAll, border: Border.all(color: AppColors.skyLight.withValues(alpha: .8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .5), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.admin_panel_settings_outlined, size: 20, color: AppColors.steel),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(role.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800, height: 1.2)),
              const SizedBox(height: 2),
              Text(role.code, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.slate, fontFamily: 'monospace')),
            ]),
          ),
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
        if (role.description != null && role.description!.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(role.description!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel, height: 1.3)),
        ],
        if (!role.isActive) ...[const SizedBox(height: AppSpacing.sm), RoleChip('Inactivo', tone: greyTone)],
      ]),
    );
  }
}
