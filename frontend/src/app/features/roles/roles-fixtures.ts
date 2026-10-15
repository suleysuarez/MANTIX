import { PermissionInfo, RoleAdmin } from '../../core/roles-admin.service';

/** Datos de prueba de las pantallas de roles. */
export function role(id: number, code: string, over: Partial<RoleAdmin> = {}): RoleAdmin {
  return {
    id, code, name: code.charAt(0) + code.slice(1).toLowerCase(), description: null, is_active: true, is_system: false,
    parent_role_id: null, parent_name: null, depth: 1, user_count: 0, children_count: 0, own_permissions: [], effective: [], ...over,
  };
}

export const PERMISSIONS: PermissionInfo[] = [
  ['tickets:ver', 'tickets', 'ver'],
  ['tickets:ver_asignados', 'tickets', 'ver_asignados'],
  ['tickets:ver_todos', 'tickets', 'ver_todos'],
  ['tickets:asignar', 'tickets', 'asignar'],
  ['usuarios:asignar', 'usuarios', 'asignar'],
].map(([code, resource, action]) => ({ code, name: code, module: resource, description: null, resource, action }));

/** Solicitante → Técnico → Supervisor, más un rol independiente. */
export const ROLES: RoleAdmin[] = [
  role(1, 'EMPLOYEE', { name: 'Solicitante', is_system: true, own_permissions: ['tickets:ver'] }),
  role(2, 'TECHNICIAN', { name: 'Técnico', is_system: true, parent_role_id: 1, parent_name: 'Solicitante', own_permissions: ['tickets:ver_asignados'] }),
  role(3, 'SUPERVISOR', { name: 'Supervisor', is_system: true, parent_role_id: 2, parent_name: 'Técnico', own_permissions: ['tickets:ver_todos', 'tickets:asignar'] }),
  role(4, 'ADMIN', { name: 'Administrador', is_system: true, parent_role_id: 3, parent_name: 'Supervisor', own_permissions: ['usuarios:asignar'] }),
  role(5, 'COMPRAS', { name: 'Compras', own_permissions: [] }),
];
