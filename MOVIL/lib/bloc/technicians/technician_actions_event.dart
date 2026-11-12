part of 'technician_actions_bloc.dart';

sealed class TechnicianActionsEvent {
  const TechnicianActionsEvent();
}

/// Abrir un perfil de técnico al usuario [userId] (`null` si aún no se eligió). [rate] es el
/// texto que escribió la persona, con coma o punto.
class TechnicianCreateRequested extends TechnicianActionsEvent {
  const TechnicianCreateRequested({required this.userId, this.specialization, this.rate});

  final int? userId;
  final String? specialization;
  final String? rate;
}

/// Cambiar la especialización y la tarifa de [technician]. Vacío borra el dato.
class TechnicianEditRequested extends TechnicianActionsEvent {
  const TechnicianEditRequested(this.technician, {this.specialization, this.rate});

  final Technician technician;
  final String? specialization;
  final String? rate;
}

/// Activar o desactivar la cuenta de usuario de [technician].
class TechnicianAccountChangeRequested extends TechnicianActionsEvent {
  const TechnicianAccountChangeRequested(this.technician, {required this.active});

  final Technician technician;
  final bool active;
}

/// Marcar a [technician] como disponible o no disponible.
class TechnicianAvailabilityRequested extends TechnicianActionsEvent {
  const TechnicianAvailabilityRequested(this.technician, {required this.available});

  final Technician technician;
  final bool available;
}
