import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/format/settings_format.dart';
import 'package:mantix/models/settings/settings_models.dart';

IntegrationHealth _item(String key, String status, {String? name}) => IntegrationHealth(key: key, name: name ?? key, status: status, detail: '');

void main() {
  group('environmentLabel', () {
    test('los entornos conocidos salen en español', () {
      expect(environmentLabel('production'), 'Producción');
      expect(environmentLabel('PRODUCTION'), 'Producción');
      expect(environmentLabel('development'), 'Desarrollo');
      expect(environmentLabel('staging'), 'Pruebas');
    });

    test('uno desconocido se muestra legible y uno vacío, con una raya', () {
      expect(environmentLabel('qa-2'), 'Qa-2');
      expect(environmentLabel(''), '—');
      expect(environmentLabel('—'), '—');
    });
  });

  group('integraciones', () {
    final all = [_item('database', 'ok', name: 'Base de datos'), _item('clerk', 'warning', name: 'Autenticación (Clerk)'), _item('storage', 'ok', name: 'Almacenamiento')];

    test('Clerk no se muestra, ni por su clave ni por su nombre', () {
      expect(visibleIntegrations(all).map((i) => i.key), ['database', 'storage']);
      expect(visibleIntegrations([_item('auth', 'ok', name: 'Autenticación (CLERK)')]), isEmpty);
    });

    test('el estado general ignora a Clerk: un aviso suyo no vuelve «a revisar» todo el sistema', () {
      expect(overallStatus(visibleIntegrations(all), 'warning'), 'ok');
    });

    test('un error visible manda sobre un aviso, y un aviso sobre lo correcto; lo desactivado no cuenta', () {
      expect(overallStatus([_item('a', 'ok'), _item('b', 'warning'), _item('c', 'error')], 'ok'), 'error');
      expect(overallStatus([_item('a', 'ok'), _item('b', 'warning')], 'ok'), 'warning');
      expect(overallStatus([_item('a', 'ok'), _item('b', 'disabled')], 'warning'), 'ok');
    });

    test('sin integraciones que mirar vale el estado del servidor', () {
      expect(overallStatus(const [], 'warning'), 'warning');
    });
  });
}
