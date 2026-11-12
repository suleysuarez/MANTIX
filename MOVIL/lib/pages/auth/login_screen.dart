import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/shared/glass_card.dart';
import '../../widgets/auth/auth_shell.dart';
import '../../repositories/auth/mobile_auth_repository.dart';

enum _AuthMode { login, register }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  _AuthMode _mode = _AuthMode.login;
  bool _busy = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  String get _title => switch (_mode) {
    _AuthMode.login => 'Bienvenido de nuevo',
    _AuthMode.register => 'Crea tu cuenta',
  };

  String get _button => switch (_mode) {
    _AuthMode.login => 'Iniciar sesión',
    _AuthMode.register => 'Crear cuenta',
  };

  void _setMode(_AuthMode mode) {
    setState(() { _mode = mode; _message = null; _password.clear(); _confirmPassword.clear(); });
  }

  String _errorText(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final detail = data['detail'];
        if (detail is String && detail.isNotEmpty) return detail;
        if (detail is Map && detail['detail'] is String) return detail['detail'] as String;
        if (data['message'] is String) return data['message'] as String;
      }
      if (error.response == null) {
        if (error.type == DioExceptionType.connectionTimeout || error.type == DioExceptionType.receiveTimeout) {
          return 'El servidor está tardando en responder. Inténtalo nuevamente.';
        }
        return 'No logramos comunicarnos con Mantix. Comprueba que el backend esté iniciado y que la dirección API sea correcta.';
      }
    }
    return 'No pudimos completar la operación. Inténtalo de nuevo.';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _busy = true; _message = null; });
    final auth = context.read<MobileAuthRepository>();
    try {
      final email = _email.text.trim();
      switch (_mode) {
        case _AuthMode.login:
          await auth.login(email: email, password: _password.text);
          break;
        case _AuthMode.register:
          final password = _password.text;
          await auth.register(email: email, password: password, firstName: _firstName.text.trim(), lastName: _lastName.text.trim());
          // La cuenta ya está lista (no hay ningún código que verificar): se entra directamente.
          try {
            await auth.login(email: email, password: password);
          } catch (_) {
            _setMode(_AuthMode.login);
            _showMessage('Tu cuenta se creó. Inicia sesión para continuar.');
          }
          break;
      }
    } catch (error) {
      if (mounted) _showMessage(_errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String value, {bool error = false}) {
    if (!mounted) return;
    setState(() { _message = value; _isError = error; });
  }

  String? _validateEmail(String? value) {
    if (value == null || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())) return 'Escribe un correo válido.';
    return null;
  }

  String? _validateFirstName(String? value) => (value == null || value.trim().isEmpty) ? 'Escribe tu nombre.' : null;

  String? _validatePassword(String? value) {
    if (value == null || value.length < 10) return 'Usa al menos 10 caracteres.';
    if (!RegExp(r'[A-Z]').hasMatch(value) || !RegExp(r'[a-z]').hasMatch(value) || !RegExp(r'\d').hasMatch(value)) return 'Incluye mayúsculas, minúsculas y números.';
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) return 'Confirma tu contraseña.';
    if (value != _password.text) return 'Las contraseñas no coinciden.';
    return null;
  }

  /// [required] añade un asterisco al nombre del campo (solo en el registro, donde hay un campo opcional).
  InputDecoration _decoration(String label, {IconData? icon, bool required = false}) => InputDecoration(
    label: required ? Text.rich(TextSpan(text: label, children: const [TextSpan(text: ' *', style: TextStyle(color: AppColors.mustard, fontWeight: FontWeight.w800))])) : null,
    labelText: required ? null : label, labelStyle: const TextStyle(color: Colors.white), floatingLabelStyle: const TextStyle(color: AuthTokens.accent), prefixIcon: icon == null ? null : Icon(icon, color: Colors.white),
    filled: true, fillColor: Colors.white.withValues(alpha: 0.10), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18))),
  );

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      child: GlassCard(
        child: Theme(
          data: AppTheme.authGlass(Theme.of(context)),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_title, textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: _mode == _AuthMode.register ? 19 : 22, fontWeight: FontWeight.w700)),
                // El registro es la tarjeta más alta: sin subtítulo para que quepa bajo el logo.
                if (_mode != _AuthMode.register) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Ingresa con tu correo y contraseña.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.45),
                  ),
                ],
                SizedBox(height: _mode == _AuthMode.register ? 12 : 22),
                if (_mode == _AuthMode.register) ...[
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: TextFormField(controller: _firstName, textCapitalization: TextCapitalization.words, maxLength: 100, decoration: _decoration('Nombre', required: true).copyWith(counterText: ''), validator: _validateFirstName)),
                    const SizedBox(width: 10),
                    Expanded(child: TextFormField(controller: _lastName, textCapitalization: TextCapitalization.words, maxLength: 100, decoration: _decoration('Apellido').copyWith(counterText: ''))),
                  ]),
                  const SizedBox(height: 10),
                ],
                ...[
                  TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, autocorrect: false, decoration: _decoration('Correo electrónico', icon: Icons.email_outlined, required: _mode == _AuthMode.register), validator: _validateEmail),
                  SizedBox(height: _mode == _AuthMode.register ? 10 : 12),
                ],
                ...[
                  TextFormField(controller: _password, obscureText: _obscure, decoration: _decoration('Contraseña', icon: Icons.lock_outline, required: _mode == _AuthMode.register).copyWith(suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Colors.white), onPressed: () => setState(() => _obscure = !_obscure))), validator: _mode == _AuthMode.login ? (v) => (v == null || v.isEmpty) ? 'Escribe tu contraseña.' : null : _validatePassword),
                  if (_mode == _AuthMode.register) ...[
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _confirmPassword,
                      obscureText: _obscureConfirm,
                      decoration: _decoration('Confirmar contraseña', icon: Icons.lock_outline, required: true).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            color: Colors.white,
                          ),
                          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                      validator: _validateConfirmPassword,
                    ),
                  ],
                  if (_mode == _AuthMode.register) const Padding(padding: EdgeInsets.only(top: 6), child: Text('* Obligatorio. Contraseña: mínimo 10 caracteres, con mayúscula, minúscula y número.', style: TextStyle(color: Color(0xFFF2C879), fontSize: 10.5, height: 1.3, fontWeight: FontWeight.w500))),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(_message!, style: TextStyle(color: _isError ? AppColors.mustard : Colors.white, fontWeight: FontWeight.w600, fontSize: 13), textAlign: TextAlign.center),
                ],
                SizedBox(height: _mode == _AuthMode.register ? 12 : 18),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_button),
                ),
                SizedBox(height: _mode == _AuthMode.register ? 4 : 12),
                if (_mode == _AuthMode.login)
                  TextButton(onPressed: () => _setMode(_AuthMode.register), child: const Text('Crear una cuenta'))
                else
                  TextButton(onPressed: () => _setMode(_AuthMode.login), child: const Text('Ya tengo una cuenta')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
