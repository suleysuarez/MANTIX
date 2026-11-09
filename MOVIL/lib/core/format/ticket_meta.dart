import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Cómo se muestra un estado o una prioridad: etiqueta en español y colores.
class ChipMeta {
  const ChipMeta({required this.label, required this.colors, this.strikethrough = false});

  final String label;
  final ChipColors colors;

  /// Los cancelados se tachan para distinguirlos sin depender solo del color.
  final bool strikethrough;
}

const Map<String, ChipMeta> _statuses = {
  'submitted': ChipMeta(label: 'Enviado', colors: StatusColors.submitted),
  'triaged': ChipMeta(label: 'En triaje', colors: StatusColors.triaged),
  'assigned': ChipMeta(label: 'Asignado', colors: StatusColors.assigned),
  'in_progress': ChipMeta(label: 'En proceso', colors: StatusColors.inProgress),
  'waiting': ChipMeta(label: 'En espera', colors: StatusColors.waiting),
  'resolved': ChipMeta(label: 'Resuelto', colors: StatusColors.resolved),
  'closed': ChipMeta(label: 'Cerrado', colors: StatusColors.closed),
  'cancelled': ChipMeta(label: 'Cancelado', colors: StatusColors.cancelled, strikethrough: true),
};

const Map<String, ChipMeta> _priorities = {
  'critical': ChipMeta(label: 'Crítica', colors: StatusColors.critical),
  'high': ChipMeta(label: 'Alta', colors: StatusColors.high),
  'medium': ChipMeta(label: 'Media', colors: StatusColors.medium),
  'low': ChipMeta(label: 'Baja', colors: StatusColors.low),
};

/// Los códigos son los de la web. Si el backend añade uno nuevo, se muestra tal
/// cual con colores neutros en vez de romper la pantalla.
ChipMeta statusMeta(String code) => _statuses[code] ?? ChipMeta(label: code, colors: StatusColors.unknown);

ChipMeta priorityMeta(String code) => _priorities[code] ?? ChipMeta(label: code, colors: StatusColors.unknown);

/// Códigos de estado conocidos, en el orden del flujo.
const List<String> knownStatuses = [
  'submitted', 'triaged', 'assigned', 'in_progress', 'waiting', 'resolved', 'closed', 'cancelled',
];

const List<String> knownPriorities = ['critical', 'high', 'medium', 'low'];

/// Icono de cada estado, para las columnas del Kanban.
IconData statusIcon(String code) => switch (code) {
      'submitted' => Icons.send_rounded,
      'triaged' => Icons.fact_check_outlined,
      'assigned' => Icons.assignment_ind_outlined,
      'in_progress' => Icons.settings_outlined,
      'waiting' => Icons.hourglass_bottom_rounded,
      'resolved' => Icons.check_circle_outline_rounded,
      'closed' => Icons.lock_outline_rounded,
      'cancelled' => Icons.cancel_outlined,
      _ => Icons.help_outline_rounded,
    };

/// Icono del ticket según su categoría (por palabras clave); equipo genérico si no hay.
IconData categoryIcon(String? category) {
  final value = (category ?? '').toLowerCase();
  if (value.contains('red') || value.contains('wifi') || value.contains('conect')) return Icons.wifi_rounded;
  if (value.contains('soft') || value.contains('sistema') || value.contains('cuenta')) return Icons.settings_outlined;
  if (value.contains('impres')) return Icons.print_outlined;
  if (value.contains('móvil') || value.contains('movil') || value.contains('telé')) return Icons.smartphone_rounded;
  return Icons.desktop_windows_outlined;
}

/// Icono de la prioridad dentro de su píldora.
IconData priorityIcon(String code) => switch (code) {
      'critical' => Icons.priority_high_rounded,
      'high' => Icons.north_east_rounded,
      'medium' => Icons.drag_handle_rounded,
      _ => Icons.south_east_rounded,
    };
