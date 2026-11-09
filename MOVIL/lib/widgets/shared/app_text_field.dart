import 'package:flutter/material.dart';

import '../../core/validation/validators.dart';

/// Campo de texto con validación del cliente y error del servidor.
///
/// [errorText] es el mensaje de un 422 para este campo (`ValidationFailure.fieldErrors`);
/// se muestra bajo el campo aunque el validador local no encuentre problema.
/// El texto se valida ya normalizado (sin espacios al inicio ni al final).
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.errorText,
    this.validator,
    this.maxLength,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.enabled = true,
    this.onChanged,
    this.prefixIcon,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? errorText;
  final Validator? validator;
  final int? maxLength;
  final int maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final Widget? prefixIcon;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      maxLines: obscureText ? 1 : maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onChanged: onChanged,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: validator == null ? null : (value) => validator!(Validators.normalize(value)),
      decoration: InputDecoration(labelText: label, hintText: hint, errorText: errorText, prefixIcon: prefixIcon),
    );
  }
}
