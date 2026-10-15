/** Texto en español de un permiso `recurso:acción`, para los avisos «Requiere permiso de…». */

const RESOURCES: Record<string, string> = {
  dashboard: 'Dashboard',
  equipos: 'Equipos',
  solicitudes: 'Solicitudes',
  tickets: 'Tickets',
  tecnicos: 'Técnicos',
  mantenimiento: 'Mantenimiento',
  inventario: 'Inventario',
  reportes: 'Reportes',
  usuarios: 'Usuarios',
  perfil: 'Perfil',
  configuracion: 'Configuración',
  auditoria: 'Auditoría',
};

const ACTIONS: Record<string, string> = {
  ver: 'ver',
  ver_asignados: 'ver lo asignado',
  ver_todos: 'ver todo',
  crear: 'crear',
  editar: 'editar',
  eliminar: 'eliminar',
  exportar: 'exportar',
  importar: 'importar',
  asignar: 'asignar',
  cambiar_estado: 'cambiar el estado',
  aprobar: 'aprobar o rechazar',
  adjuntar: 'adjuntar archivos',
  consumir: 'consumir',
};

/** «tickets:asignar» → «Tickets · asignar». Un código desconocido se muestra tal cual, sin inventar. */
export function permissionLabel(code: string): string {
  const [resource, action] = code.split(':');
  const name = RESOURCES[resource];
  const verb = ACTIONS[action];
  return name && verb ? `${name} · ${verb}` : code;
}

/** Aviso de un botón deshabilitado por falta de permiso. */
export function requiresText(codes: string | readonly string[]): string {
  const list = typeof codes === 'string' ? [codes] : codes;
  return `Requiere permiso de ${list.map(permissionLabel).join(' o ')}`;
}
