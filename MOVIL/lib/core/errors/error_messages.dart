/// Mensajes propios para los códigos de error específicos que la app necesita distinguir
/// (`docs/error-codes.md`). Un código que no esté aquí no es un error: la app usa el
/// mensaje genérico del estado HTTP. Un test comprueba que cada clave exista en la
/// tabla del backend, para que un renombrado no deje un mensaje huérfano.
const Map<String, String> messagesByErrorCode = {
  // Tickets
  'ticket_not_found': 'Este ticket ya no existe.',
  'ticket_requires_technician': 'Asigna un técnico al ticket antes de avanzar su estado.',
  'ticket_assign_wrong_status': 'En su estado actual ya no se puede asignar técnico a este ticket.',
  'ticket_classify_wrong_status': 'Solo se clasifican las solicitudes que esperan triaje.',
  'ticket_reject_wrong_status': 'Solo se pueden rechazar las solicitudes que aún no empezaron.',
  'ticket_record_without_technician': 'No se puede registrar trabajo: el ticket no tiene técnico asignado.',
  'ticket_view_forbidden': 'No tienes acceso a este ticket.',
  'ticket_act_forbidden': 'Solo el técnico asignado o un supervisor puede actuar sobre este ticket.',
  'invalid_transition': 'Ese cambio de estado no está permitido desde el estado actual del ticket.',
  'technician_inactive': 'Ese técnico está inactivo y no puede recibir tickets.',
  'technician_not_found': 'Ese técnico ya no existe.',
  'no_active_assignment': 'Este ticket no tiene un técnico asignado.',
  // Equipos
  'equipment_not_found': 'Ese equipo ya no existe.',
  'equipment_identifier_taken': 'Ya existe un equipo con esa etiqueta o número de serie.',
  'equipment_serial_taken': 'Ya existe un equipo con ese número de serie.',
  // Adjuntos
  'attachment_not_found': 'Ese archivo ya no existe.',
  'attachment_limit_reached': 'Se alcanzó el máximo de archivos adjuntos.',
  'attachment_equipment_forbidden': 'No tienes permiso para adjuntar archivos a equipos.',
  'attachment_delete_forbidden': 'Solo quien subió el archivo o un supervisor puede eliminarlo.',
  'attachment_access_forbidden': 'No tienes acceso a este archivo.',
  // Catálogos y cuentas
  'priority_not_found': 'Esa prioridad no existe o está inactiva.',
  'category_not_found': 'Esa categoría no existe o está inactiva.',
  'user_inactive': 'Tu usuario está inactivo. Habla con un administrador.',
  'user_account_disabled': 'Esa cuenta está desactivada.',
};
