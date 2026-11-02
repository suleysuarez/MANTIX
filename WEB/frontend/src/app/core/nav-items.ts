export interface NavItem {
  label: string;
  /** Nombre del icono de Material Symbols. */
  icon: string;
  path: string;
  /** Permiso local requerido; sin él, el enlace es visible para todo usuario autorizado. */
  permission?: string;
  /** Roles que lo ven (cualquiera); sin él, basta el permiso. Los permisos solos no distinguen al técnico. */
  roles?: readonly string[];
}

export const NAV_ITEMS: readonly NavItem[] = [
  { label: 'Dashboard', icon: 'home', path: '/dashboard' },
  { label: 'Equipos', icon: 'desktop_windows', path: '/equipos', permission: 'equipos:ver' },
  { label: 'Tickets', icon: 'confirmation_number', path: '/tickets', permission: 'tickets:ver' },
  { label: 'Solicitudes', icon: 'inbox', path: '/solicitudes', permission: 'solicitudes:ver_todos' },
  { label: 'Técnicos', icon: 'engineering', path: '/technicians', permission: 'tecnicos:ver' },
  { label: 'Mantenimiento', icon: 'event_repeat', path: '/mantenimiento', permission: 'mantenimiento:ver' },
  { label: 'Inventario', icon: 'inventory_2', path: '/inventario', permission: 'inventario:ver' },
  { label: 'Reportes', icon: 'monitoring', path: '/reportes', permission: 'reportes:ver' },
  { label: 'Usuarios', icon: 'manage_accounts', path: '/usuarios', permission: 'usuarios:ver' },
  { label: 'Roles y permisos', icon: 'admin_panel_settings', path: '/roles', permission: 'usuarios:asignar' },
  { label: 'Usuarios pendientes', icon: 'how_to_reg', path: '/admin/pending-users', permission: 'usuarios:asignar' },
  { label: 'Configuración', icon: 'settings', path: '/configuracion', permission: 'configuracion:ver' },
];

/** Solo los enlaces que el usuario puede usar. Las rutas siguen protegidas por sus guards. */
export function visibleNavItems(permissionCodes: readonly string[], roleCodes: readonly string[] = []): NavItem[] {
  return NAV_ITEMS.filter(
    (item) =>
      (!item.permission || permissionCodes.includes(item.permission)) &&
      (!item.roles || item.roles.some((role) => roleCodes.includes(role))),
  );
}
