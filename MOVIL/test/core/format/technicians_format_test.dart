import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/format/technicians_format.dart';
import 'package:mantix/models/technicians/technician_filters.dart';
import 'package:mantix/models/technicians/technician_models.dart';

import '../../support/technicians_support.dart';

Technician _tech(int id, String name, {String? specialization, bool available = true, bool active = true, String? code}) =>
    Technician.fromJson(technicianJson(id: id, name: name, specialization: specialization, available: available, active: active, code: code));

void main() {
  // Las reglas son las de `technician-ui.ts` de la web.
  final sofia = _tech(1, 'Sofía Ruiz', specialization: 'Hardware, Redes', code: 'TEC-01');
  final bruno = _tech(2, 'Bruno Paz', specialization: 'Software');
  final ana = _tech(3, 'Ana Gil', specialization: 'redes; Impresoras', available: false);
  final zoe = _tech(4, 'Zoe Mar', specialization: null, active: false);
  final all = [sofia, bruno, ana, zoe];
  final workload = Workload.fromJson(workloadJson({1: (3, 10), 2: (0, 21), 3: (1, 2)}));

  List<String> names(Iterable<Technician> technicians) => [for (final t in technicians) t.fullName];

  group('estado operativo', () {
    test('no disponible manda sobre la carga', () => expect(technicianStatus(ana, workload), TechnicianStatus.unavailable));
    test('disponible con tickets abiertos: ocupado', () => expect(technicianStatus(sofia, workload), TechnicianStatus.busy));
    test('disponible sin tickets: libre', () => expect(technicianStatus(bruno, workload), TechnicianStatus.free));
    test('sin datos de carga nadie está ocupado', () => expect(technicianStatus(sofia, null), TechnicianStatus.free));

    test('el texto cuenta los tickets de quien está ocupado', () {
      expect(statusText(sofia, workload), '3 tickets activos');
      expect(statusText(_tech(3, 'Ana Gil'), workload), '1 ticket activo');
      expect(statusText(bruno, workload), 'Disponible');
      expect(statusText(ana, workload), 'No disponible');
    });
  });

  group('especialidades', () {
    test('el texto libre se parte por comas y punto y coma', () {
      expect(specialties(sofia), ['Hardware', 'Redes']);
      expect(specialties(ana), ['redes', 'Impresoras']);
      expect(specialties(zoe), isEmpty);
      expect(specialties(_tech(9, 'X', specialization: ' , Redes ,, ')), ['Redes']);
    });

    test('la lista no repite por mayúsculas ni tildes y va en orden', () {
      expect(allSpecialties(all), ['Hardware', 'Impresoras', 'Redes', 'Software']);
    });

    test('normalize quita tildes y mayúsculas', () => expect(normalize('SOFÍA Núñez'), 'sofia nunez'));
  });

  test('loadBucket: ninguno, 1 a 2, 3 o más', () {
    expect(loadBucket(0), LoadBucket.none);
    expect(loadBucket(1), LoadBucket.low);
    expect(loadBucket(2), LoadBucket.low);
    expect(loadBucket(3), LoadBucket.high);
  });

  group('filterTechnicians', () {
    test('por defecto ordena por menor carga y, a igual carga, por nombre', () {
      expect(names(filterTechnicians(all, workload, const TechnicianFilters())), ['Bruno Paz', 'Zoe Mar', 'Ana Gil', 'Sofía Ruiz']);
    });

    test('la búsqueda ignora tildes y mira nombre, correo y especialidad, pero ya no el código', () {
      expect(names(filterTechnicians(all, workload, const TechnicianFilters(search: ' sofia '))), ['Sofía Ruiz']);
      expect(names(filterTechnicians(all, workload, const TechnicianFilters(search: 'tec-01'))), isEmpty, reason: 'el código de empleado ya no se muestra ni se busca');
      expect(names(filterTechnicians(all, workload, const TechnicianFilters(search: 'tech2@'))), ['Bruno Paz']);
      expect(names(filterTechnicians(all, workload, const TechnicianFilters(search: 'IMPRESORAS'))), ['Ana Gil']);
    });

    test('la tarjeta de resumen filtra por estado operativo', () {
      expect(names(filterTechnicians(all, workload, const TechnicianFilters(status: TechnicianStatus.busy))), ['Sofía Ruiz']);
      expect(names(filterTechnicians(all, workload, const TechnicianFilters(status: TechnicianStatus.free))), ['Bruno Paz']);
      expect(names(filterTechnicians(all, workload, const TechnicianFilters(status: TechnicianStatus.unavailable))), ['Zoe Mar', 'Ana Gil']);
    });

    test('varias especialidades: basta con tener una', () {
      expect(names(filterTechnicians(all, workload, const TechnicianFilters(specialties: {'redes'}))), ['Ana Gil', 'Sofía Ruiz']);
      expect(names(filterTechnicians(all, workload, const TechnicianFilters(specialties: {'redes', 'software'}))), ['Bruno Paz', 'Ana Gil', 'Sofía Ruiz']);
    });

    test('cuenta, disponibilidad y carga', () {
      expect(names(filterTechnicians(all, workload, const TechnicianFilters(accounts: {false}))), ['Zoe Mar']);
      expect(names(filterTechnicians(all, workload, const TechnicianFilters(availability: {false}))), ['Ana Gil']);
      expect(names(filterTechnicians(all, workload, const TechnicianFilters(loads: {LoadBucket.high}))), ['Sofía Ruiz']);
      expect(names(filterTechnicians(all, workload, const TechnicianFilters(loads: {LoadBucket.none, LoadBucket.low}))), ['Bruno Paz', 'Zoe Mar', 'Ana Gil']);
      expect(names(filterTechnicians(all, workload, const TechnicianFilters(accounts: {true, false}))).length, 4, reason: 'elegir las dos opciones no filtra');
    });

    test('los filtros se combinan', () {
      expect(filterTechnicians(all, workload, const TechnicianFilters(specialties: {'redes'}, availability: {true}, loads: {LoadBucket.none})), isEmpty);
    });

    test('los otros órdenes', () {
      expect(names(filterTechnicians(all, workload, const TechnicianFilters(), order: TechnicianOrder.name)), ['Ana Gil', 'Bruno Paz', 'Sofía Ruiz', 'Zoe Mar']);
      expect(names(filterTechnicians(all, workload, const TechnicianFilters(), order: TechnicianOrder.resolved)), ['Bruno Paz', 'Sofía Ruiz', 'Ana Gil', 'Zoe Mar']);
      expect(names(filterTechnicians(all, workload, const TechnicianFilters(), order: TechnicianOrder.availability)), ['Bruno Paz', 'Sofía Ruiz', 'Ana Gil', 'Zoe Mar']);
    });

    test('el técnico recién registrado sale primero', () {
      expect(names(filterTechnicians(all, workload, const TechnicianFilters(), pinnedId: 1)).first, 'Sofía Ruiz');
    });

    test('sin datos de carga ordena por nombre y el filtro de carga trata a todos como sin tickets', () {
      expect(names(filterTechnicians(all, null, const TechnicianFilters())), ['Ana Gil', 'Bruno Paz', 'Sofía Ruiz', 'Zoe Mar']);
      expect(filterTechnicians(all, null, const TechnicianFilters(loads: {LoadBucket.high})), isEmpty);
    });
  });

  group('summarize', () {
    test('cuenta sobre todos los técnicos', () {
      final summary = summarize(all, workload);
      expect(summary, const TechnicianSummary(total: 4, available: 2, busy: 1, unavailable: 2, openTickets: 4, resolved: 33, overloaded: 1));
      expect(summary.free, 1);
    });

    test('sin carga no hay ocupados ni tickets', () {
      expect(summarize(all, null), const TechnicianSummary(total: 4, available: 2, unavailable: 2));
    });
  });

  group('filtros', () {
    test('activeCount cuenta los grupos de la hoja, no la búsqueda ni la tarjeta', () {
      expect(const TechnicianFilters().activeCount, 0);
      expect(const TechnicianFilters().isEmpty, isTrue);
      expect(const TechnicianFilters(search: 'ana', status: TechnicianStatus.free).activeCount, 0);
      expect(const TechnicianFilters(search: 'ana').isEmpty, isFalse);
      expect(const TechnicianFilters(specialties: {'redes'}, loads: {LoadBucket.low, LoadBucket.high}).activeCount, 2);
    });

    test('copyWith puede quitar la tarjeta de resumen', () {
      const filters = TechnicianFilters(status: TechnicianStatus.busy, search: 'x');
      expect(filters.copyWith(clearStatus: true), const TechnicianFilters(search: 'x'));
    });
  });

  group('validación', () {
    test('la especialización admite hasta 100 caracteres sin contar espacios sobrantes', () {
      expect(specializationError(null), isNull);
      expect(specializationError('  ${'a' * 100}  '), isNull);
      expect(specializationError('a' * 101), 'La especialización no puede superar los 100 caracteres.');
    });

    test('la tarifa vacía es válida', () {
      expect(rateError(null), isNull);
      expect(rateError('   '), isNull);
    });

    test('la tarifa admite coma o punto y hasta dos decimales', () {
      for (final ok in ['0', '35', '35.5', '35,50', ' 12,05 ', '99999999.99']) {
        expect(rateError(ok), isNull, reason: ok);
      }
    });

    test('ni negativos ni texto', () {
      for (final bad in ['-1', '-0,5', 'abc', '1e3', '1.2.3', '1,2,3', '.5', '5.', r'$35']) {
        expect(rateError(bad), 'La tarifa por hora debe ser un número igual o mayor a cero.', reason: bad);
      }
    });

    test('más de dos decimales', () {
      expect(rateError('35.123'), 'La tarifa por hora admite como máximo dos decimales.');
      expect(rateError('0,001'), 'La tarifa por hora admite como máximo dos decimales.');
    });

    test('por encima del máximo de la base de datos', () {
      expect(rateError('100000000'), 'La tarifa por hora supera el máximo permitido.');
    });

    test('parseRate entiende coma y punto', () {
      expect(parseRate(''), isNull);
      expect(parseRate('35,5'), 35.5);
      expect(parseRate(' 35.50 '), 35.5);
    });
  });

  group('formato de la tarifa', () {
    test('dos decimales con coma', () {
      expect(formatRate(35), r'$35,00');
      expect(formatRate(12.5), r'$12,50');
      expect(formatRate(null), '—');
    });

    test('para volver a editarla', () {
      expect(rateInput(35.5), '35,50');
      expect(rateInput(null), '');
    });
  });

  test('etiquetas en español', () {
    expect(TechnicianStatus.values.map(statusLabel), ['Disponible', 'Con tickets activos', 'No disponible']);
    expect(LoadBucket.values.map(loadLabel), ['Sin tickets', '1 a 2 tickets', '3 o más tickets']);
    expect(TechnicianOrder.values.map(orderLabel), ['Menor carga de tickets', 'Disponibilidad', 'Más tickets resueltos', 'Nombre']);
  });
}
