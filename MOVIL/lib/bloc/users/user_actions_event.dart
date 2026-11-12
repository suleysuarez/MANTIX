part of 'user_actions_bloc.dart';

sealed class UserActionsEvent {
  const UserActionsEvent();
}

/// Reemplazar los roles de una persona por [roleIds]. Sirve igual para un pendiente (sin
/// [currentRoleIds]). [name] sale en los mensajes.
class UserRolesChangeRequested extends UserActionsEvent {
  const UserRolesChangeRequested({required this.userId, required this.name, required this.roleIds, this.currentRoleIds = const []});

  final int userId;
  final String name;
  final List<int> roleIds;

  /// Los roles que ya tiene, para no pedir nada si la selección no cambia.
  final List<int> currentRoleIds;
}

/// Activar o desactivar la cuenta de [user].
class UserActiveChangeRequested extends UserActionsEvent {
  const UserActiveChangeRequested(this.user, {required this.active});

  final ManagedUser user;
  final bool active;
}

/// Cambiar el teléfono de [user]. Vacío lo borra.
class UserContactChangeRequested extends UserActionsEvent {
  const UserContactChangeRequested(this.user, {this.phone});

  final ManagedUser user;
  final String? phone;
}
