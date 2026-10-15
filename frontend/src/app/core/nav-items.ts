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
  { label: 'Equipos', icon: 'desktop_windows', path: '/equipos', permission: 'equipment.read' },
  { label: 'Tickets', icon: 'confirmation_number', path: '/tickets', permission: 'maintenance.read' },
  { label: 'Solicitudes', icon: 'inbox', path: '/solicitudes', permission: 'maintenance.manage', roles: ['ADMIN', 'SUPERVISOR'] },
  { label: 'Técnicos', icon: 'engineering', path: '/technicians', permission: 'maintenance.read' },
  { label: 'Mantenimiento', icon: 'event_repeat', path: '/mantenimiento', permission: 'maintenance.read' },
  { label: 'Mantenimientos', icon: 'build', path: '/maintenance', permission: 'maintenance.read' },
  { label: 'Inventario', icon: 'inventory_2', path: '/inventario', permission: 'inventory.read' },
  { label: 'Reportes', icon: 'monitoring', path: '/reportes', permission: 'maintenance.read' },
  { label: 'Usuarios pendientes', icon: 'how_to_reg', path: '/admin/pending-users', permission: 'users.manage' },
  { label: 'Configuración', icon: 'settings', path: '/configuracion', permission: 'users.manage' },
];

/** Solo los enlaces que el usuario puede usar. Las rutas siguen protegidas por sus guards. */
export function visibleNavItems(permissionCodes: readonly string[], roleCodes: readonly string[] = []): NavItem[] {
  return NAV_ITEMS.filter(
    (item) =>
      (!item.permission || permissionCodes.includes(item.permission)) &&
      (!item.roles || item.roles.some((role) => roleCodes.includes(role))),
  );
}
