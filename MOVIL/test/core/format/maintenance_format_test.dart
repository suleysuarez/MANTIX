import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/format/maintenance_format.dart';

void main() {
  group('título', () {
    test('es obligatorio y de 3 a 200 caracteres sin contar espacios sobrantes', () {
      expect(planTitleError(null), 'Este campo es obligatorio.');
      expect(planTitleError('    '), 'Este campo es obligatorio.');
      expect(planTitleError(' ab '), 'Debe tener al menos 3 caracteres.');
      expect(planTitleError(' abc '), isNull);
      expect(planTitleError('a' * 200), isNull);
      expect(planTitleError('a' * 201), 'Debe tener como máximo 200 caracteres.');
    });
  });

  group('descripción', () {
    test('es opcional, no puede ser solo espacios y tiene máximo', () {
      expect(planDescriptionError(null), isNull);
      expect(planDescriptionError(''), isNull);
      expect(planDescriptionError('   '), 'No puede contener solo espacios.');
      expect(planDescriptionError('a' * 2000), isNull);
      expect(planDescriptionError('a' * 2001), 'Debe tener como máximo 2000 caracteres.');
    });
  });

  group('cada cuántos días', () {
    test('entero de 1 a 3650', () {
      expect(intervalError(''), 'Este campo es obligatorio.');
      expect(intervalError('2,5'), 'Debe ser un número entero.');
      expect(intervalError('abc'), 'Debe ser un número entero.');
      expect(intervalError('0'), 'Debe ser al menos 1.');
      expect(intervalError('-3'), 'Debe ser al menos 1.');
      expect(intervalError('1'), isNull);
      expect(intervalError(' 30 '), isNull);
      expect(intervalError('3650'), isNull);
      expect(intervalError('3651'), 'No puede ser mayor que 3650.');
    });
  });

  group('recordatorio', () {
    test('entero de 0 a 365', () {
      expect(remindError('', '30'), 'Este campo es obligatorio.');
      expect(remindError('1.5', '30'), 'Debe ser un número entero.');
      expect(remindError('-1', '30'), 'Debe ser al menos 0.');
      expect(remindError('0', '30'), isNull);
      expect(remindError('366', '3650'), 'No puede ser mayor que 365.');
    });

    test('no puede superar el intervalo entre servicios', () {
      expect(remindError('31', '30'), 'El recordatorio no puede superar el intervalo entre servicios.');
      expect(remindError('30', '30'), isNull);
    });

    test('con un intervalo que no es válido no se compara', () {
      expect(remindError('5', ''), isNull);
      expect(remindError('5', 'abc'), isNull);
    });
  });

  group('primer servicio', () {
    final now = DateTime(2026, 10, 25, 10);

    test('es obligatorio', () => expect(firstDueError(null, now), 'Este campo es obligatorio.'));
    test('no puede estar en el pasado', () => expect(firstDueError(DateTime(2026, 10, 25, 9, 59), now), 'No se puede programar en el pasado.'));
    test('puede ser ahora mismo o después', () {
      expect(firstDueError(now, now), isNull);
      expect(firstDueError(DateTime(2026, 11, 26, 9), now), isNull);
    });
  });

  group('horas', () {
    test('vacías valen', () {
      expect(hoursError(null), isNull);
      expect(hoursError('  '), isNull);
    });

    test('admiten coma o punto y hasta dos decimales', () {
      for (final ok in ['1', '1.5', '1,5', '0.25', ' 12,05 ', '999']) {
        expect(hoursError(ok), isNull, reason: ok);
      }
    });

    test('mayores que 0 y hasta 999', () {
      expect(hoursError('0'), 'Debe ser mayor que 0.');
      expect(hoursError('0,00'), 'Debe ser mayor que 0.');
      expect(hoursError('999,01'), 'No puede ser mayor que 999.');
      expect(hoursError('1000'), 'No puede ser mayor que 999.');
    });

    test('ni texto ni negativos ni tres decimales', () {
      for (final bad in ['abc', '-1', '1e3', '1.2.3', '.5', r'$5']) {
        expect(hoursError(bad), 'Escribe un número válido.', reason: bad);
      }
      expect(hoursError('1,234'), 'Usa como máximo 2 decimales.');
    });

    test('parseHours entiende coma y punto', () {
      expect(parseHours(''), isNull);
      expect(parseHours(null), isNull);
      expect(parseHours('1,5'), 1.5);
      expect(parseHours(' 2.25 '), 2.25);
    });
  });

  test('las horas de un plan se muestran con coma y sin ceros de más', () {
    expect(formatPlanHours(null), '—');
    expect(formatPlanHours(1.5), '1,5 h');
    expect(formatPlanHours(2), '2 h');
    expect(formatPlanHours(0.25), '0,25 h');
    expect(formatPlanHours(10), '10 h');
  });

  test('el intervalo se lee en español', () {
    expect(intervalText(1), 'Cada día');
    expect(intervalText(30), 'Cada 30 días');
  });

  test('el formulario propone 30 días y 3 de antelación', () {
    expect(defaultIntervalDays, 30);
    expect(defaultRemindDays, 3);
  });
}
