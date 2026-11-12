import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../home/mantix_drawer.dart' show initialsOf;
import '../shared/app_chip.dart';
import '../users/user_cards.dart' show RoleChip, roleIcon;

/// Qué hacer con la foto.
enum PhotoAction { camera, gallery, remove }

/// Menú de la foto: tomar una, elegirla de la galería o quitar la actual (solo si [hasPhoto]).
Future<PhotoAction?> showPhotoMenu(BuildContext context, {required bool hasPhoto}) => showModalBottomSheet<PhotoAction>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.white,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.lg),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined, color: AppColors.steel), title: const Text('Tomar una foto'), onTap: () => Navigator.pop(sheet, PhotoAction.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined, color: AppColors.steel), title: const Text('Elegir de la galería'), onTap: () => Navigator.pop(sheet, PhotoAction.gallery)),
          if (hasPhoto) ListTile(leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error), title: const Text('Quitar mi foto'), onTap: () => Navigator.pop(sheet, PhotoAction.remove)),
        ]),
      ),
    );

/// Un rol con su código (para el icono) y el nombre que se lee.
typedef RoleLabel = ({String code, String name});

/// La tarjeta de arriba: mi foto (o mis iniciales), nombre, correo, roles y el estado de la cuenta.
/// Con [canEditPhoto] la foto lleva una cámara que abre el menú; [saving] la tapa con un indicador.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({super.key, required this.name, required this.email, required this.roles, required this.avatar, required this.canEditPhoto, required this.saving, required this.onPhoto});

  final String name;
  final String email;
  final List<RoleLabel> roles;
  final Uint8List? avatar;
  final bool canEditPhoto;
  final bool saving;
  final VoidCallback onPhoto;

  static const _size = 96.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.skyLight, AppColors.sky], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: AppRadius.lgAll,
      ),
      child: Column(children: [
        Semantics(
          label: canEditPhoto ? 'Mi foto. Toca para cambiarla.' : 'Mi foto',
          button: canEditPhoto,
          child: GestureDetector(
            onTap: canEditPhoto && !saving ? onPhoto : null,
            child: SizedBox(
              width: _size + 10,
              height: _size + 6,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: Container(
                    width: _size,
                    height: _size,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.white, border: Border.all(color: AppColors.white, width: 3)),
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.center,
                    child: avatar != null
                        // Una foto dañada no rompe la pantalla: se muestran las iniciales.
                        ? Image.memory(avatar!, width: _size, height: _size, fit: BoxFit.cover, gaplessPlayback: true, excludeFromSemantics: true, errorBuilder: (context, error, stack) => _Initials(name))
                        : _Initials(name),
                  ),
                ),
                if (saving)
                  Positioned.fill(
                    right: 10,
                    bottom: 6,
                    child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.navy.withValues(alpha: .45)), child: const Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.white)))),
                  ),
                if (canEditPhoto)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: AppColors.mustard, shape: BoxShape.circle, border: Border.all(color: AppColors.white, width: 2)),
                      child: const Icon(Icons.photo_camera_rounded, size: 18, color: AppColors.navy),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // El nombre completo está en «Mis datos»: aquí se acota para que un nombre larguísimo, con la
        // letra grande y en una pantalla estrecha, no empuje el resto fuera de la vista.
        Text(name, maxLines: 3, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900, height: 1.15)),
        const SizedBox(height: 2),
        Text(email, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.steel)),
        const SizedBox(height: AppSpacing.md),
        Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
          for (final role in roles) RoleChip(role.name, icon: roleIcon(role.code)),
          const AppChip(label: 'Cuenta activa', colors: StatusColors.resolved, semanticPrefix: 'Estado'),
        ]),
      ]),
    );
  }
}

/// Las iniciales de la persona, cuando no hay foto o no se puede mostrar.
class _Initials extends StatelessWidget {
  const _Initials(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => Text(initialsOf(name), style: const TextStyle(color: AppColors.steel, fontSize: 34, fontWeight: FontWeight.w900));
}
