import 'package:flutter/material.dart';

import '../../core/format/users_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/users/user_models.dart';
import '../shared/mantix_sheet.dart';

/// Lo que se escribió en la hoja de contacto, tal cual (el Bloc lo normaliza y compara).
typedef UserContactInput = ({String phone});

/// Hoja para editar el teléfono de [user]. Devuelve lo escrito o `null`
/// si se cierra sin guardar. No manda nada al servidor. El nombre y el correo no se editan aquí.
Future<UserContactInput?> showContactSheet(BuildContext context, {required ManagedUser user}) => showMantixSheet<UserContactInput>(
      context,
      title: 'Editar datos de contacto',
      initialHeight: .7,
      builder: (sheetContext, controller) => _ContactBody(user: user, controller: controller),
    );

class _ContactBody extends StatefulWidget {
  const _ContactBody({required this.user, required this.controller});

  final ManagedUser user;
  final ScrollController controller;

  @override
  State<_ContactBody> createState() => _ContactBodyState();
}

class _ContactBodyState extends State<_ContactBody> {
  late final _phone = TextEditingController(text: widget.user.phone ?? '');

  /// El error solo se enseña cuando la persona ya escribió en el campo.
  bool _phoneTouched = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phoneProblem = phoneError(_phone.text);
    final valid = phoneProblem == null;
    return Column(children: [
      Expanded(
        child: ListView(controller: widget.controller, padding: const EdgeInsets.all(AppSpacing.lg), children: [
          Text(widget.user.fullName, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(widget.user.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel)),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            maxLength: phoneMaxLength,
            onChanged: (_) => setState(() => _phoneTouched = true),
            decoration: InputDecoration(labelText: 'Teléfono', hintText: '+57 300 123 4567', prefixIcon: const Icon(Icons.phone_outlined), errorText: _phoneTouched ? phoneProblem : null, errorMaxLines: 2),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Déjalo vacío para borrar el teléfono. El nombre y el correo no se cambian desde aquí.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate, height: 1.3)),
        ]),
      ),
      Container(
        decoration: BoxDecoration(color: AppColors.white, border: Border(top: BorderSide(color: AppColors.grey.withValues(alpha: .6)))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: FilledButton.icon(
              onPressed: valid ? () => Navigator.of(context).pop((phone: _phone.text)) : null,
              icon: const Icon(Icons.check_rounded),
              label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Guardar cambios', maxLines: 1)),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
          ),
        ),
      ),
    ]);
  }
}
