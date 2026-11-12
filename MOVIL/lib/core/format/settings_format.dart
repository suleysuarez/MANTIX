/// Textos y reglas de la pantalla de configuración. Funciones puras.
library;

import '../../models/settings/settings_models.dart';

/// El nombre del entorno en español. Lo manda el servidor (la variable `APP_ENV`); un valor que la
/// app no conoce se muestra tal cual, con la primera letra en mayúscula.
String environmentLabel(String name) {
  final value = name.trim().toLowerCase();
  return switch (value) {
    'production' || 'prod' || 'produccion' || 'producción' => 'Producción',
    'development' || 'dev' || 'desarrollo' => 'Desarrollo',
    'staging' || 'test' || 'testing' => 'Pruebas',
    '' || '—' => '—',
    _ => '${value[0].toUpperCase()}${value.substring(1)}',
  };
}

bool _isClerk(IntegrationHealth item) => item.key.toLowerCase().contains('clerk') || item.name.toLowerCase().contains('clerk');

/// Las integraciones que se muestran. La app móvil no usa Clerk (es solo de la web): su estado no
/// se enseña aquí, ni cuenta para el estado general.
List<IntegrationHealth> visibleIntegrations(List<IntegrationHealth> items) => [for (final item in items) if (!_isClerk(item)) item];

/// El estado general de lo que se ve: `error` si algo falla; `warning` si algo no está del todo bien;
/// `ok` si todo funciona (lo desactivado no cuenta). Sin integraciones que mirar, vale el del servidor.
String overallStatus(List<IntegrationHealth> visible, String serverOverall) {
  if (visible.isEmpty) return serverOverall;
  if (visible.any((item) => item.status == 'error')) return 'error';
  if (visible.any((item) => item.status != 'ok' && item.status != 'disabled')) return 'warning';
  return 'ok';
}
