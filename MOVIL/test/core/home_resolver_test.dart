import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/routing/home_resolver.dart';

void main() {
  group('resolveHome', () {
    test('dashboard global exige dashboard:ver_todos Y tickets:ver_todos', () {
      expect(resolveHome({'dashboard:ver_todos', 'tickets:ver_todos'}), HomeDestination.globalDashboard);
    });

    test('dashboard:ver_todos sin tickets:ver_todos cae en reportes', () {
      expect(resolveHome({'dashboard:ver_todos', 'reportes:ver'}), HomeDestination.reports);
    });

    test('dashboard:ver_todos sin tickets:ver_todos ni reportes cae en el dashboard propio solo si tiene dashboard:ver', () {
      expect(resolveHome({'dashboard:ver_todos'}), HomeDestination.profile);
      expect(resolveHome({'dashboard:ver_todos', 'dashboard:ver'}), HomeDestination.ownDashboard);
    });

    test('tickets:ver_asignados lleva a la bandeja de trabajo', () {
      expect(resolveHome({'tickets:ver_asignados', 'dashboard:ver'}), HomeDestination.assignedInbox);
    });

    test('solicitudes:ver lleva a mis solicitudes', () {
      expect(resolveHome({'solicitudes:ver', 'reportes:ver', 'dashboard:ver'}), HomeDestination.myRequests);
    });

    test('reportes:ver gana al dashboard propio', () {
      expect(resolveHome({'reportes:ver', 'dashboard:ver'}), HomeDestination.reports);
    });

    test('sin ningún criterio, Perfil', () {
      expect(resolveHome({}), HomeDestination.profile);
      expect(resolveHome({'tickets:ver'}), HomeDestination.profile);
    });

    test('el orden es el del plan aunque lleguen todos los permisos', () {
      final all = {
        'dashboard:ver_todos',
        'tickets:ver_todos',
        'tickets:ver_asignados',
        'solicitudes:ver',
        'reportes:ver',
        'dashboard:ver',
      };
      expect(resolveHome(all), HomeDestination.globalDashboard);
      expect(resolveHome(all..remove('tickets:ver_todos')), HomeDestination.assignedInbox);
      expect(resolveHome(all..remove('tickets:ver_asignados')), HomeDestination.myRequests);
      expect(resolveHome(all..remove('solicitudes:ver')), HomeDestination.reports);
      expect(resolveHome(all..remove('reportes:ver')), HomeDestination.ownDashboard);
    });
  });
}
