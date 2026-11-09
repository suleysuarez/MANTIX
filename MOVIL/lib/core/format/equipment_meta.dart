import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'ticket_meta.dart';

/// Estados de un equipo: etiqueta en español y tono, igual que en la web. Un código
/// nuevo se muestra tal cual, en neutro, en vez de romper la pantalla.
const Map<String, ChipMeta> _statuses = {
  'in_storage': ChipMeta(label: 'En almacén', colors: EquipmentColors.ok),
  'assigned': ChipMeta(label: 'Asignado', colors: EquipmentColors.ok),
  'in_repair': ChipMeta(label: 'En mantenimiento', colors: EquipmentColors.warn),
  'lost': ChipMeta(label: 'Extraviado', colors: EquipmentColors.bad),
  'retired': ChipMeta(label: 'Retirado', colors: EquipmentColors.bad),
  'disposed': ChipMeta(label: 'Dado de baja', colors: EquipmentColors.bad),
};

ChipMeta equipmentStatusMeta(String code) => _statuses[code] ?? ChipMeta(label: code, colors: EquipmentColors.neutral);

/// Icono por categoría (códigos del catálogo de la web).
IconData equipmentCategoryIcon(String typeCode) => switch (typeCode.toUpperCase()) {
      'LAPTOP' => Icons.laptop_mac_rounded,
      'DESKTOP' => Icons.desktop_windows_rounded,
      'MONITOR' => Icons.monitor_rounded,
      'PRINTER' => Icons.print_rounded,
      'SERVER' => Icons.dns_rounded,
      'NETWORK_EQUIPMENT' => Icons.router_rounded,
      'MOBILE_DEVICE' => Icons.smartphone_rounded,
      _ => Icons.devices_other_rounded,
    };
