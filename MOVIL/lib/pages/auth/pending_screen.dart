import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/auth/auth_shell.dart';
import '../../widgets/shared/glass_card.dart';

/// Cuenta autenticada sin ningún rol: acaba de crearse y espera que un administrador le asigne uno.
///
/// Dice qué pasó (la cuenta ya existe), a nombre de quién está, qué falta y qué hacer: el avance en
/// tres pasos y «Volver a comprobar» para cuando ya tenga rol. La app no avisa sola, así que no lo
/// promete.
class PendingScreen extends StatelessWidget {
  const PendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<AuthBloc>();
    final profile = context.watch<AuthBloc>().state.profile;
    return AuthShell(
      child: GlassCard(
        child: Theme(
          data: AppTheme.authGlass(Theme.of(context)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: AppColors.mustard.withValues(alpha: .22), shape: BoxShape.circle, border: Border.all(color: AppColors.mustard, width: 2)),
                  child: const Icon(Icons.hourglass_top_rounded, color: AppColors.mustard, size: 28),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Cuenta pendiente de aprobación', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, height: 1.2)),
              const SizedBox(height: 6),
              const Text('¡Tu cuenta ya está creada!', textAlign: TextAlign.center, style: TextStyle(color: AppColors.mustard, fontSize: 14, fontWeight: FontWeight.w700)),
              if (profile != null) ...[
                const SizedBox(height: 14),
                _Account(name: profile.fullName, email: profile.email),
              ],
              const SizedBox(height: 16),
              const _Step(state: _StepState.done, title: 'Cuenta creada', detail: 'Ya iniciaste sesión.'),
              const _Step(state: _StepState.current, title: 'Un administrador te asigna un rol', detail: 'Hasta entonces no puedes usar Mantix.'),
              const _Step(state: _StepState.next, title: 'Empiezas a usar Mantix', detail: 'Cuando tengas rol, toca «Volver a comprobar».', last: true),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => bloc.add(const AuthRefreshRequested()),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Volver a comprobar'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.mustard, foregroundColor: AppColors.navy, minimumSize: const Size.fromHeight(50), textStyle: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 4),
              TextButton(onPressed: () => bloc.add(const AuthSignOutRequested()), child: const Text('Cerrar sesión')),
            ],
          ),
        ),
      ),
    );
  }
}

/// A nombre de quién está la cuenta, para que quien se equivocó de correo lo vea de inmediato.
class _Account extends StatelessWidget {
  const _Account({required this.name, required this.email});

  final String name;
  final String email;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .10), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: .18))),
        child: Row(children: [
          const Icon(Icons.person_outline_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
              Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
        ]),
      );
}

enum _StepState { done, current, next }

/// Un paso del avance: hecho (marca), en curso (reloj, en mostaza) o pendiente (círculo vacío).
class _Step extends StatelessWidget {
  const _Step({required this.state, required this.title, required this.detail, this.last = false});

  final _StepState state;
  final String title;
  final String detail;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final done = state == _StepState.done;
    final current = state == _StepState.current;
    return Semantics(
      container: true,
      label: '${done ? 'Hecho' : current ? 'En curso' : 'Pendiente'}: $title. $detail',
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 28,
            child: Column(children: [
              Icon(done ? Icons.check_circle_rounded : current ? Icons.timelapse_rounded : Icons.radio_button_unchecked_rounded, size: 24, color: done || current ? AppColors.mustard : Colors.white54),
              if (!last) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: done ? AppColors.mustard : Colors.white24)),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: current ? FontWeight.w800 : FontWeight.w700, height: 1.25)),
                const SizedBox(height: 2),
                Text(detail, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
