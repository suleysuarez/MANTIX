import 'package:flutter/material.dart';

import '../../core/format/users_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../shared/mantix_sheet.dart';

/// Lo que se escribió en la hoja, tal cual (el Bloc lo normaliza y compara con lo que ya hay).
typedef ProfileEditInput = ({String fullName, String phone});

/// Hoja para editar mi nombre y mi teléfono. El correo se muestra pero no se edita: es la
/// identidad con la que se inicia sesión. Devuelve lo escrito o `null` si se cierra sin guardar.
Future<ProfileEditInput?> showProfileEditSheet(BuildContext context, {required String fullName, required String? phone, required String email}) => showMantixSheet<ProfileEditInput>(
      context,
      title: 'Editar mis datos',
      initialHeight: .72,
      builder: (sheetContext, controller) => _EditBody(fullName: fullName, phone: phone ?? '', email: email, controller: controller),
    );

class _EditBody extends StatefulWidget {
  const _EditBody({required this.fullName, required this.phone, required this.email, required this.controller});

  final String fullName;
  final String phone;
  final String email;
  final ScrollController controller;

  @override
  State<_EditBody> createState() => _EditBodyState();
}

class _EditBodyState extends State<_EditBody> {
  late final _name = TextEditingController(text: widget.fullName);
  late final _phone = TextEditingController(text: widget.phone);

  /// El error de cada campo solo se enseña cuando la persona ya escribió en él.
  bool _nameTouched = false;
  bool _phoneTouched = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  String? get _nameProblem {
    final name = collapseSpaces(_name.text);
    if (name.length < 2) return 'Escribe tu nombre (al menos 2 letras).';
    if (name.length > 120) return 'El nombre admite hasta 120 caracteres.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phoneProblem = phoneError(_phone.text);
    final valid = _nameProblem == null && phoneProblem == null;
    return Column(children: [
      Expanded(
        child: ListView(controller: widget.controller, padding: const EdgeInsets.all(AppSpacing.lg), children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            maxLength: 120,
            onChanged: (_) => setState(() => _nameTouched = true),
            decoration: InputDecoration(labelText: 'Nombre completo', prefixIcon: const Icon(Icons.person_outline_rounded), counterText: '', errorText: _nameTouched ? _nameProblem : null, errorMaxLines: 2),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            maxLength: phoneMaxLength,
            onChanged: (_) => setState(() => _phoneTouched = true),
            decoration: InputDecoration(labelText: 'Teléfono', hintText: '+57 300 123 4567', prefixIcon: const Icon(Icons.phone_outlined), counterText: '', errorText: _phoneTouched ? phoneProblem : null, errorMaxLines: 2),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            initialValue: widget.email,
            enabled: false,
            decoration: const InputDecoration(labelText: 'Correo electrónico', prefixIcon: Icon(Icons.email_outlined)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Déjalo vacío para borrar el teléfono. El correo es tu usuario para iniciar sesión y no se cambia desde aquí.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate, height: 1.3)),
        ]),
      ),
      Container(
        decoration: BoxDecoration(color: AppColors.white, border: Border(top: BorderSide(color: AppColors.grey.withValues(alpha: .6)))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: FilledButton.icon(
              onPressed: valid ? () => Navigator.of(context).pop((fullName: _name.text, phone: _phone.text)) : null,
              icon: const Icon(Icons.check_rounded),
              label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Guardar cambios', maxLines: 1)),
              style: FilledButton.styleFrom(backgroundColor: AppColors.mustard, foregroundColor: AppColors.navy, minimumSize: const Size.fromHeight(52)),
            ),
          ),
        ),
      ),
    ]);
  }
}
