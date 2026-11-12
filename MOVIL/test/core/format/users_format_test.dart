import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/format/users_format.dart';

void main() {
  group('estado de la cuenta (igual que la web)', () {
    final login = DateTime(2026, 11, 1);

    test('la inactiva manda sobre todo', () {
      expect(accessState(isActive: false, lastLoginAt: login), AccessState.inactive);
      expect(accessState(isActive: false, lastLoginAt: null), AccessState.inactive);
    });
    test('activa y nunca entró: pendiente de primer ingreso', () => expect(accessState(isActive: true, lastLoginAt: null), AccessState.never));
    test('activa y ya entró: activa', () => expect(accessState(isActive: true, lastLoginAt: login), AccessState.active));
    test('etiquetas en español', () {
      expect(accessLabel(AccessState.active), 'Activo');
      expect(accessLabel(AccessState.inactive), 'Inactivo');
      expect(accessLabel(AccessState.never), 'Pendiente de primer ingreso');
    });
  });

  group('lastAccessText', () {
    final now = DateTime(2026, 11, 9, 12);

    test('nunca', () => expect(lastAccessText(null, now), 'Nunca'));
    test('ahora mismo', () => expect(lastAccessText(now.subtract(const Duration(seconds: 20)), now), 'Ahora mismo'));
    test('minutos', () => expect(lastAccessText(now.subtract(const Duration(minutes: 5)), now), 'Hace 5 min'));
    test('horas', () => expect(lastAccessText(now.subtract(const Duration(hours: 3, minutes: 10)), now), 'Hace 3 h'));
    test('días, en singular y plural', () {
      expect(lastAccessText(now.subtract(const Duration(days: 1, hours: 2)), now), 'Hace 1 día');
      expect(lastAccessText(now.subtract(const Duration(days: 12)), now), 'Hace 12 días');
    });
    test('pasado un mes, la fecha', () => expect(lastAccessText(DateTime(2026, 8, 3), now), '3 ago 2026'));
  });

  group('teléfono', () {
    test('vacío es válido (es opcional)', () {
      expect(phoneError(null), isNull);
      expect(phoneError('   '), isNull);
    });
    test('formatos válidos', () {
      expect(phoneError('+57 300 123 4567'), isNull);
      expect(phoneError('601 (5) 555-0100'), isNull, reason: 'admite paréntesis y guiones después del primer dígito');
      expect(phoneError('3001234567'), isNull);
    });
    test('letras o muy corto', () {
      const message = 'El teléfono solo admite números, espacios, +, ( ) y -.';
      expect(phoneError('abc12345'), message);
      expect(phoneError('12345'), message);
      expect(phoneError('(601) 555-0100'), message, reason: 'como el backend: debe empezar por + o un dígito');
      expect(phoneError('+${'1' * 30}'), message);
    });
    test('se normaliza juntando espacios y el vacío queda nulo', () {
      expect(normalizedPhone('  +57   300  123 '), '+57 300 123');
      expect(normalizedPhone('   '), isNull);
      expect(normalizedPhone(null), isNull);
    });
  });

  group('código de empleado', () {
    test('vacío es válido', () => expect(employeeCodeError(' '), isNull));
    test('válidos', () {
      expect(employeeCodeError('EMP-014'), isNull);
      expect(employeeCodeError('a1'), isNull);
      expect(employeeCodeError('ab.cd_12-3'), isNull);
    });
    test('inválidos', () {
      const message = 'El código solo admite letras, números, punto, guion y guion bajo (2 a 50).';
      expect(employeeCodeError('x'), message);
      expect(employeeCodeError('-abc'), message);
      expect(employeeCodeError('con espacio'), message);
      expect(employeeCodeError('a' * 51), message);
    });
    test('se normaliza en mayúsculas, como lo guarda el servidor', () {
      expect(normalizedEmployeeCode(' emp-014 '), 'EMP-014');
      expect(normalizedEmployeeCode(''), isNull);
    });
  });

  test('rolesError: al menos uno y como máximo diez', () {
    expect(rolesError(const []), 'Elige al menos un rol.');
    expect(rolesError(const [1]), isNull);
    expect(rolesError(List.generate(10, (i) => i + 1)), isNull);
    expect(rolesError(List.generate(11, (i) => i + 1)), 'Un usuario admite como máximo 10 roles.');
    expect(rolesError(const [1, 1, 1]), isNull, reason: 'los repetidos cuentan una vez');
  });

  test('collapseSpaces', () => expect(collapseSpaces('  Ana   Pérez  '), 'Ana Pérez'));
}
