export interface NavItem {
  label: string;
  path: string;
  /** Permiso local requerido; sin él, el enlace es visible para todo usuario autorizado. */
  permission?: string;
}

export const NAV_ITEMS: readonly NavItem[] = [
  { label: 'Dashboard', path: '/dashboard' },
  { label: 'Equipment', path: '/equipos', permission: 'equipment.read' },
  { label: 'Maintenance', path: '/maintenance', permission: 'maintenance.read' },
  { label: 'Technicians', path: '/technicians', permission: 'maintenance.read' },
  { label: 'Pending users', path: '/admin/pending-users', permission: 'users.manage' },
];

/** Solo los enlaces que el usuario puede usar. Las rutas siguen protegidas por sus guards. */
export function visibleNavItems(permissionCodes: readonly string[]): NavItem[] {
  return NAV_ITEMS.filter((item) => !item.permission || permissionCodes.includes(item.permission));
}
