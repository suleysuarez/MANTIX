/// Textos de la pantalla de perfil. Funciones puras.
library;

const _titles = {
  'auth.login': 'Iniciaste sesión',
  'profile.updated': 'Actualizaste tus datos',
  'profile.avatar_updated': 'Cambiaste tu foto',
  'profile.avatar_removed': 'Quitaste tu foto',
  'profile.password_changed': 'Cambiaste tu contraseña',
  'roles.replaced': 'Cambiaron tus roles',
  'user.activated': 'Activaron tu cuenta',
  'user.created': 'Crearon tu cuenta',
  'user.updated': 'Actualizaron tus datos',
  'user.password_reset': 'Restablecieron tu contraseña',
};

/// Qué pasó, en español. Una acción que la app no conoce se muestra legible en vez de romper.
String historyTitle(String action) {
  final known = _titles[action];
  if (known != null) return known;
  final text = action.replaceAll(RegExp(r'[._]+'), ' ').trim();
  return text.isEmpty ? 'Actividad' : '${text[0].toUpperCase()}${text.substring(1)}';
}

/// Nombre del tipo de actividad.
String historyKindLabel(String kind) => switch (kind) {
      'session' => 'Sesión',
      'profile' => 'Datos personales',
      'security' => 'Seguridad',
      _ => 'Actividad',
    };
