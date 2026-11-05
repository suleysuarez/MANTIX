import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/auth/bloc/auth_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/glass_card.dart';
import 'widgets/auth_shell.dart';
import '../data/mobile_auth_repository.dart';

enum _AuthMode { login, register, verify, forgot, reset }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  _AuthMode _mode = _AuthMode.login;
  bool _busy = false;
  bool _obscure = true;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _title => switch (_mode) {
    _AuthMode.login => 'Bienvenido de nuevo',
    _AuthMode.register => 'Crea tu cuenta',
    _AuthMode.verify => 'Verifica tu correo',
    _AuthMode.forgot => 'Recupera tu cuenta',
    _AuthMode.reset => 'Nueva contraseña',
  };

  String get _button => switch (_mode) {
    _AuthMode.login => 'Iniciar sesión',
    _AuthMode.register => 'Crear cuenta',
    _AuthMode.verify => 'Verificar y continuar',
    _AuthMode.forgot => 'Enviar código',
    _AuthMode.reset => 'Guardar contraseña',
  };

  void _setMode(_AuthMode mode) {
    setState(() { _mode = mode; _message = null; _code.clear(); _password.clear(); });
  }

  String _errorText(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['detail'] is String) return data['detail'] as String;
      if (error.response == null) return 'No pudimos conectar con el servidor. Revisa tu conexión.';
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
          if (mounted) context.read<AuthBloc>().add(const AuthRefreshRequested());
        case _AuthMode.register:
          await auth.register(fullName: _name.text.trim(), email: email, password: _password.text);
          _setMode(_AuthMode.verify);
          _showMessage('Te enviamos un código de 6 dígitos a tu correo.');
        case _AuthMode.verify:
          await auth.verifyEmail(email: email, code: _code.text.trim());
          if (mounted) context.read<AuthBloc>().add(const AuthRefreshRequested());
        case _AuthMode.forgot:
          await auth.requestPasswordReset(email);
          _setMode(_AuthMode.reset);
          _showMessage('Si la cuenta existe, recibirás un código para restablecer la contraseña.');
        case _AuthMode.reset:
          await auth.resetPassword(email: email, code: _code.text.trim(), newPassword: _password.text);
          _setMode(_AuthMode.login);
          _showMessage('Contraseña actualizada. Ya puedes iniciar sesión.');
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

  String? _validatePassword(String? value) {
    if (value == null || value.length < 10) return 'Usa al menos 10 caracteres.';
    if (!RegExp(r'[A-Z]').hasMatch(value) || !RegExp(r'[a-z]').hasMatch(value) || !RegExp(r'\d').hasMatch(value)) return 'Incluye mayúsculas, minúsculas y números.';
    return null;
  }

  InputDecoration _decoration(String label, {IconData? icon}) => InputDecoration(
    labelText: label, prefixIcon: icon == null ? null : Icon(icon),
    filled: true, fillColor: Colors.white.withValues(alpha: 0.08),
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
                Text(_title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  switch (_mode) {
                    _AuthMode.login => 'Ingresa con tu correo y contraseña.',
                    _AuthMode.register => 'Regístrate. Un administrador habilitará tu acceso.',
                    _AuthMode.verify => 'Escribe el código que enviamos a tu correo.',
                    _AuthMode.forgot => 'Te enviaremos un código si tu cuenta está registrada.',
                    _AuthMode.reset => 'Ingresa el código recibido y tu nueva contraseña.',
                  },
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                if (_mode == _AuthMode.register) ...[
                  TextFormField(controller: _name, textCapitalization: TextCapitalization.words, decoration: _decoration('Nombre completo', icon: Icons.person_outline), validator: (v) => (v == null || v.trim().length < 2) ? 'Escribe tu nombre.' : null),
                  const SizedBox(height: 12),
                ],
                if (_mode != _AuthMode.verify && _mode != _AuthMode.reset) ...[
                  TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, autocorrect: false, decoration: _decoration('Correo electrónico', icon: Icons.email_outlined), validator: _validateEmail),
                  const SizedBox(height: 12),
                ],
                if (_mode == _AuthMode.verify || _mode == _AuthMode.reset) ...[
                  if (_email.text.isEmpty)
                    TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: _decoration('Correo electrónico'), validator: _validateEmail),
                  const SizedBox(height: 12),
                  TextFormField(controller: _code, keyboardType: TextInputType.number, maxLength: 6, decoration: _decoration('Código de 6 dígitos', icon: Icons.pin_outlined), validator: (v) => (v == null || !RegExp(r'^\d{6}$').hasMatch(v.trim())) ? 'Ingresa el código de 6 dígitos.' : null),
                  const SizedBox(height: 4),
                ],
                if (_mode == _AuthMode.login || _mode == _AuthMode.register || _mode == _AuthMode.reset) ...[
                  TextFormField(controller: _password, obscureText: _obscure, decoration: _decoration('Contraseña', icon: Icons.lock_outline).copyWith(suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => _obscure = !_obscure))), validator: _mode == _AuthMode.login ? (v) => (v == null || v.isEmpty) ? 'Escribe tu contraseña.' : null : _validatePassword),
                  if (_mode != _AuthMode.login) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Mínimo 10 caracteres, una mayúscula, una minúscula y un número.', style: TextStyle(fontSize: 11))),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(_message!, style: TextStyle(color: _isError ? Colors.redAccent : Colors.lightGreenAccent), textAlign: TextAlign.center),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_button),
                ),
                const SizedBox(height: 12),
                if (_mode == _AuthMode.login) ...[
                  TextButton(onPressed: () => _setMode(_AuthMode.forgot), child: const Text('¿Olvidaste tu contraseña?')),
                  TextButton(onPressed: () => _setMode(_AuthMode.register), child: const Text('Crear una cuenta')),
                ] else if (_mode == _AuthMode.register) ...[
                  TextButton(onPressed: () => _setMode(_AuthMode.login), child: const Text('Ya tengo una cuenta')),
                ] else if (_mode == _AuthMode.verify) ...[
                  TextButton(onPressed: _busy ? null : () async {
                    try { await auth.resendVerification(_email.text.trim()); _showMessage('Si la cuenta necesita verificación, enviaremos otro código.'); }
                    catch (error) { _showMessage(_errorText(error), error: true); }
                  }, child: const Text('Reenviar código')),
                ] else ...[
                  TextButton(onPressed: () => _setMode(_AuthMode.login), child: const Text('Volver a iniciar sesión')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
