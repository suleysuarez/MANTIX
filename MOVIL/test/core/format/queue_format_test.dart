import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/format/queue_format.dart';
import 'package:mantix/models/catalogs/catalog_models.dart';

const _priorities = [
  PriorityOption(code: 'low', name: 'Baja', level: 1),
  PriorityOption(code: 'critical', name: 'Crítica', level: 4),
  PriorityOption(code: 'medium', name: 'Media', level: 2),
  PriorityOption(code: 'high', name: 'Alta', level: 3),
];

void main() {
  group('formatHours (igual que la web)', () {
    test('sin dato', () => expect(formatHours(null), '—'));
    test('menos de una hora, en minutos y como mínimo 1', () {
      expect(formatHours(0.25), '15 min');
      expect(formatHours(0.001), '1 min');
      expect(formatHours(0), '1 min');
    });
    test('hasta 48 horas, con coma decimal y sin «,0»', () {
      expect(formatHours(12.5), '12,5 h');
      expect(formatHours(12), '12 h');
      expect(formatHours(24.1), '24,1 h');
      expect(formatHours(47.9), '47,9 h');
    });
    test('desde 48 horas, en días', () {
      expect(formatHours(48), '2 d');
      expect(formatHours(72), '3 d');
      expect(formatHours(245), '10,2 d');
    });
  });

  test('formatPct usa coma decimal', () {
    expect(formatPct(null), '—');
    expect(formatPct(87.5), '87,5%');
    expect(formatPct(100), '100%');
    expect(formatPct(0), '0%');
  });

  test('formatChange: flecha, igual o vacío sin base de comparación', () {
    expect(formatChange(null), '');
    expect(formatChange(12.5), '▲ 12,5%');
    expect(formatChange(-50), '▼ 50%');
    expect(formatChange(0), '= 0%');
  });

  test('changeTone depende de si subir es bueno', () {
    expect(changeTone(null, betterWhenHigher: true), ChangeTone.neutral);
    expect(changeTone(0, betterWhenHigher: false), ChangeTone.neutral);
    expect(changeTone(10, betterWhenHigher: true), ChangeTone.good);
    expect(changeTone(-10, betterWhenHigher: true), ChangeTone.bad);
    // El tiempo de primera respuesta es mejor cuando baja.
    expect(changeTone(10, betterWhenHigher: false), ChangeTone.bad);
    expect(changeTone(-10, betterWhenHigher: false), ChangeTone.good);
  });

  group('espera de una solicitud', () {
    final now = DateTime.utc(2026, 11, 9, 12);

    test('waitHours nunca es negativa', () {
      expect(waitHours(now.subtract(const Duration(hours: 5)), now), 5);
      expect(waitHours(now.add(const Duration(hours: 3)), now), 0);
    });

    test('waitTone: fresca, envejeciendo y vieja', () {
      expect(waitTone(23.9), WaitTone.fresh);
      expect(waitTone(24), WaitTone.aging);
      expect(waitTone(71.9), WaitTone.aging);
      expect(waitTone(72), WaitTone.stale);
    });
  });

  test('columnText da el rótulo de la web y, si el estado es nuevo, el nombre general', () {
    expect(columnText('submitted', fallback: 'Enviado'), (title: 'Recibidas', hint: 'Esperan clasificación'));
    expect(columnText('triaged', fallback: 'En triaje').title, 'Clasificadas');
    expect(columnText('assigned', fallback: 'Asignado').hint, 'Con técnico, sin iniciar');
    expect(columnText('on_hold', fallback: 'En pausa'), (title: 'En pausa', hint: ''));
  });

  test('categoryLabel', () {
    const names = {'network': 'Red'};
    expect(categoryLabel(null, names), 'Sin categoría');
    expect(categoryLabel('', names), 'Sin categoría');
    expect(categoryLabel('uncategorized', names), 'Sin categoría');
    expect(categoryLabel('network', names), 'Red');
    expect(categoryLabel('legacy', names), 'legacy');
  });

  test('share: proporción con un mínimo visible para lo que no es cero', () {
    expect(share(0, 10), 0);
    expect(share(5, 10), 50);
    expect(share(1, 100), 4);
    expect(share(3, 0), 0);
    expect(share(10, 10), 100);
  });

  group('prioridades según la tabla del servidor', () {
    test('el tono sale de la posición, de la más urgente (0) a la menos (3)', () {
      expect([for (final code in ['critical', 'high', 'medium', 'low']) priorityTone(code, _priorities)], [0, 1, 2, 3]);
    });
    test('con menos prioridades se reparte igual', () {
      const two = [PriorityOption(code: 'a', name: 'A', level: 2), PriorityOption(code: 'b', name: 'B', level: 1)];
      expect(priorityTone('a', two), 0);
      expect(priorityTone('b', two), 2);
    });
    test('un código desconocido usa el tono más débil y el nombre es el código', () {
      expect(priorityTone('mystery', _priorities), 3);
      expect(priorityName('mystery', _priorities), 'mystery');
      expect(priorityName('critical', _priorities), 'Crítica');
    });
  });

  group('motivo de rechazo', () {
    test('mensajes en español', () {
      expect(reasonError(null), 'Escribe el motivo del rechazo.');
      expect(reasonError('      '), 'Escribe el motivo del rechazo.');
      expect(reasonError('  abc  '), 'El motivo debe tener al menos 5 caracteres.');
      expect(reasonError('a' * 501), 'El motivo admite como máximo 500 caracteres.');
    });
    test('válido: cuenta sin los espacios sobrantes', () {
      expect(reasonError('  abcde '), isNull);
      expect(reasonError('a' * 500), isNull);
    });
  });

  group('rango de fechas', () {
    final today = DateTime(2026, 11, 9, 15);

    test('válido o vacío', () {
      expect(queueRangeError(null, null, today), isNull);
      expect(queueRangeError(DateTime(2026, 11, 1), DateTime(2026, 11, 9), today), isNull);
      expect(queueRangeError(DateTime(2026, 11, 9), DateTime(2026, 11, 9), today), isNull);
      expect(queueRangeError(null, DateTime(2026, 12, 1), today), isNull);
    });
    test('la inicial no es futura', () => expect(queueRangeError(DateTime(2026, 11, 10), null, today), 'La fecha inicial no puede ser futura.'));
    test('la final no es anterior', () => expect(queueRangeError(DateTime(2026, 11, 5), DateTime(2026, 11, 4), today), 'La fecha final no puede ser anterior a la inicial.'));
    test('máximo 366 días', () {
      expect(queueRangeError(DateTime(2025, 11, 9), DateTime(2026, 11, 9), today), isNull, reason: '366 días contando ambos extremos');
      expect(queueRangeError(DateTime(2025, 11, 8), DateTime(2026, 11, 9), today), 'El rango no puede superar 366 días.');
    });
  });

  test('moveLabel: las columnas con su nombre y cancelar como «Rechazar»', () {
    expect(moveLabel('triaged', fallback: 'En triaje'), 'Clasificadas');
    expect(moveLabel('assigned', fallback: 'Asignado'), 'Asignadas');
    expect(moveLabel('cancelled', fallback: 'Cancelado'), 'Rechazar');
    expect(moveLabel('in_progress', fallback: 'En proceso'), 'En proceso');
  });

  test('periodLabel: el periodo que devuelve el servidor, o nada si no se reconoce', () {
    expect(periodLabel('30d'), '30 días');
    expect(periodLabel('7d'), '7 días');
    expect(periodLabel('1d'), '1 día');
    expect(periodLabel('12m'), '12 meses');
    expect(periodLabel('1m'), '1 mes');
    expect(periodLabel(null), isNull);
    expect(periodLabel('todo'), isNull);
  });
}
