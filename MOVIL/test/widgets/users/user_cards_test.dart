import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/widgets/users/user_cards.dart';

void main() {
  group('icono de cada rol (solo decora)', () {
    test('cada rol conocido tiene el suyo', () {
      expect(roleIcon('ADMIN'), Icons.settings_rounded);
      expect(roleIcon('SUPERVISOR'), Icons.verified_user_outlined);
      expect(roleIcon('TECHNICIAN'), Icons.build_rounded);
      expect(roleIcon('EMPLOYEE'), Icons.person_add_alt_1_outlined);
      expect(roleIcon('AUDITOR'), Icons.description_outlined);
    });

    test('no distingue mayúsculas y un rol desconocido usa el escudo genérico', () {
      expect(roleIcon('admin'), Icons.settings_rounded);
      expect(roleIcon('NUEVO_ROL'), Icons.admin_panel_settings_outlined);
      expect(roleIcon(''), Icons.admin_panel_settings_outlined);
    });
  });
}
