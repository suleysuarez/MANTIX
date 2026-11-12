/// Reglas y textos de la pantalla de usuarios. Funciones puras, portadas de la web
/// (`users-ui.ts`) y del backend (`schemas/user_management.py`) para que las tres digan lo mismo.
library;

import 'formatters.dart';

/// Cómo está una cuenta: la inactiva manda; si está activa y nunca entró, queda pendiente de su
/// primer ingreso.
enum AccessState { active, inactive, never }

AccessState accessState({required bool isActive, required DateTime? lastLoginAt}) {
  if (!isActive) return AccessState.inactive;
  return lastLoginAt == null ? AccessState.never : AccessState.active;
}

String accessLabel(AccessState state) => switch (state) {
      AccessState.active => 'Activo',
      AccessState.inactive => 'Inactivo',
      AccessState.never => 'Pendiente de primer ingreso',
    };

/// «Nunca», «Ahora mismo», «Hace 5 min», «Hace 3 h», «Hace 2 días» o la fecha si pasó un mes.
String lastAccessText(DateTime? value, DateTime now) {
  if (value == null) return 'Nunca';
  final minutes = now.difference(value).inMinutes;
  if (minutes < 1) return 'Ahora mismo';
  if (minutes < 60) return 'Hace $minutes min';
  final hours = minutes ~/ 60;
  if (hours < 24) return 'Hace $hours h';
  final days = hours ~/ 24;
  if (days < 30) return 'Hace $days ${days == 1 ? 'día' : 'días'}';
  return formatDate(value);
}

/// Límites del backend para teléfono, código de empleado y cantidad de roles.
const phoneMaxLength = 25;
const employeeCodeMaxLength = 50;
const maxRolesPerUser = 10;

final _phone = RegExp(r'^\+?[0-9][0-9 ()-]{5,24}$');
final _code = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{1,49}$');

/// Quita los espacios sobrantes y junta los repetidos, como el backend.
String collapseSpaces(String value) => value.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Error del teléfono, en español, o `null` si es válido o está vacío (es opcional).
String? phoneError(String? value) {
  final phone = collapseSpaces(value ?? '');
  if (phone.isEmpty) return null;
  if (phone.length > phoneMaxLength || !_phone.hasMatch(phone)) return 'El teléfono solo admite números, espacios, +, ( ) y -.';
  return null;
}

/// Error del código de empleado, en español, o `null` si es válido o está vacío (es opcional).
String? employeeCodeError(String? value) {
  final code = (value ?? '').trim();
  if (code.isEmpty) return null;
  if (!_code.hasMatch(code)) return 'El código solo admite letras, números, punto, guion y guion bajo (2 a 50).';
  return null;
}

/// Teléfono normalizado para enviarlo; `null` si quedó vacío (el servidor lo borra).
String? normalizedPhone(String? value) {
  final phone = collapseSpaces(value ?? '');
  return phone.isEmpty ? null : phone;
}

/// Código de empleado normalizado: el servidor lo guarda en mayúsculas; `null` si quedó vacío.
String? normalizedEmployeeCode(String? value) {
  final code = (value ?? '').trim();
  return code.isEmpty ? null : code.toUpperCase();
}

/// Error de la selección de roles al asignar, o `null` si es válida.
String? rolesError(Iterable<int> roleIds) {
  final unique = roleIds.toSet();
  if (unique.isEmpty) return 'Elige al menos un rol.';
  if (unique.length > maxRolesPerUser) return 'Un usuario admite como máximo $maxRolesPerUser roles.';
  return null;
}
