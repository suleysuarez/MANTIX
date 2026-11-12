import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/format/profile_format.dart';
import 'package:mantix/models/profile/profile_models.dart';

import '../../support/profile_support.dart';

void main() {
  group('ProfileData', () {
    test('lee el perfil con sus roles, su foto y sus fechas', () {
      final profile = ProfileData.fromJson(profileJson(hasAvatar: true, avatarVersion: 3));

      expect((profile.id, profile.email, profile.fullName, profile.phone), (1, 'ana@mantix.test', 'Ana Pérez', '+57 300 123 4567'));
      expect(profile.roles.single.code, 'TECHNICIAN');
      expect(profile.roles.single.name, 'Técnico');
      expect((profile.hasAvatar, profile.avatarVersion), (true, 3));
      expect(profile.lastLoginAt, isNotNull);
      expect(profile.createdAt.year, 2026);
    });

    test('tolera un teléfono y un último acceso ausentes', () {
      final profile = ProfileData.fromJson(profileJson(phone: null, lastLogin: null));

      expect(profile.phone, isNull);
      expect(profile.lastLoginAt, isNull);
      expect(profile.hasAvatar, isFalse);
      expect(profile.avatarVersion, isNull);
    });
  });

  group('HistoryEntry', () {
    test('lee quién lo hizo cuando fue otra persona', () {
      final mine = HistoryEntry.fromJson(historyJson());
      final others = HistoryEntry.fromJson(historyJson(action: 'roles.replaced', kind: 'security', actor: 'Admin Demo'));

      expect((mine.action, mine.kind, mine.actorName), ('auth.login', 'session', null));
      expect((others.kind, others.actorName), ('security', 'Admin Demo'));
    });
  });

  group('textos del historial', () {
    test('las acciones conocidas salen en español', () {
      expect(historyTitle('auth.login'), 'Iniciaste sesión');
      expect(historyTitle('profile.updated'), 'Actualizaste tus datos');
      expect(historyTitle('profile.avatar_updated'), 'Cambiaste tu foto');
      expect(historyTitle('roles.replaced'), 'Cambiaron tus roles');
    });

    test('una acción desconocida se muestra legible y sin romper', () {
      expect(historyTitle('report.exported_pdf'), 'Report exported pdf');
      expect(historyTitle(''), 'Actividad');
    });

    test('cada tipo tiene su nombre', () {
      expect([for (final kind in ['session', 'profile', 'security', 'activity', 'otro']) historyKindLabel(kind)], ['Sesión', 'Datos personales', 'Seguridad', 'Actividad', 'Actividad']);
    });
  });
}
