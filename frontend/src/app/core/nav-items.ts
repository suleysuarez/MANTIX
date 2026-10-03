export interface NavItem {
  label: string;
  /** Nombre del icono de Material Symbols. */
  icon: string;
  path: string;
  /** Permiso local requerido; sin él, el enlace es visible para todo usuario autorizado. */
  permission?: string;
}

export const NAV_ITEMS: readonly NavItem[] = [
  { label: 'Dashboard', icon: 'dashboard', path: '/dashboard' },
  { label: 'Equipment', icon: 'devices', path: '/equipos', permission: 'equipment.read' },
  { label: 'Maintenance', icon: 'build', path: '/maintenance', permission: 'maintenance.read' },
  { label: 'Technicians', icon: 'engineering', path: '/technicians', permission: 'maintenance.read' },
  { label: 'Pending users', icon: 'how_to_reg', path: '/admin/pending-users', permission: 'users.manage' },
];

/** Solo los enlaces que el usuario puede usar. Las rutas siguen protegidas por sus guards. */
export function visibleNavItems(permissionCodes: readonly string[]): NavItem[] {
  return NAV_ITEMS.filter((item) => !item.permission || permissionCodes.includes(item.permission));
}
