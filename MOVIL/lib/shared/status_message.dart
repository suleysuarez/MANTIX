import 'package:flutter/material.dart';

/// Pantalla de mensaje centrada: icono, título, texto y acciones opcionales.
/// La usan los estados de acceso (pendiente, sin acceso, sin conexión).
class StatusMessage extends StatelessWidget {
  const StatusMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                    child: Icon(icon, size: 40, color: theme.colorScheme.primary, semanticLabel: title),
                  ),
                  const SizedBox(height: 24),
                  Text(title, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    for (final action in actions) Padding(padding: const EdgeInsets.only(bottom: 8), child: action),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
