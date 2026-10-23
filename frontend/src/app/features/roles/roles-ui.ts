import { NavItem, visibleNavItems } from '../../core/nav-items';
import { actionLabel, resourceLabel } from '../../core/permission-labels';
import { PermissionInfo, RoleAdmin } from '../../core/roles-admin.service';

export const ADMIN_CODE = 'ADMIN';

export const ROLE_LIMITS = { nameMin: 3, nameMax: 100, descriptionMax: 500 } as const;

/** Cambios sin guardar: id del rol → permisos propios que quedarían. */
export type Draft = ReadonlyMap<number, ReadonlySet<string>>;

export interface MatrixRow {
  code: string;
  action: string;
  actionLabel: string;
  description: string | null;
}

export interface MatrixGroup {
  resource: string;
  label: string;
  rows: MatrixRow[];
}

export interface RoleFormValues {
  name: string;
  description: string;
  parent_role_id: number | null;
}

export interface RoleFormErrors {
  name?: string;
  description?: string;
}

/** Permisos `recurso:acción` agrupados por recurso, en el orden del catálogo (los del modelo viejo se omiten). */
export function buildMatrix(permissions: readonly PermissionInfo[]): MatrixGroup[] {
  const groups = new Map<string, MatrixGroup>();
  for (const permission of permissions) {
    if (!permission.resource || !permission.action) {
      continue;
    }
    let group = groups.get(permission.resource);
    if (!group) {
      group = { resource: permission.resource, label: resourceLabel(permission.resource), rows: [] };
      groups.set(permission.resource, group);
    }
    group.rows.push({
      code: permission.code,
      action: permission.action,
      actionLabel: actionLabel(permission.action),
      description: permission.description,
    });
  }
  return [...groups.values()];
}

export function validateRoleForm(values: RoleFormValues, roles: readonly RoleAdmin[], editingId: number | null): RoleFormErrors {
  const errors: RoleFormErrors = {};
  const name = values.name.trim();
  if (!name) {
    errors.name = 'Escribe el nombre del rol.';
  } else if (name.length < ROLE_LIMITS.nameMin) {
    errors.name = `Debe tener al menos ${ROLE_LIMITS.nameMin} caracteres.`;
  } else if (name.length > ROLE_LIMITS.nameMax) {
    errors.name = `Debe tener como máximo ${ROLE_LIMITS.nameMax} caracteres.`;
  } else if (roles.some((role) => role.id !== editingId && role.name.trim().toLowerCase() === name.toLowerCase())) {
    errors.name = 'Ya existe un rol con ese nombre.';
  }
  if (values.description.trim().length > ROLE_LIMITS.descriptionMax) {
    errors.description = `Debe tener como máximo ${ROLE_LIMITS.descriptionMax} caracteres.`;
  }
  return errors;
}

export function hasErrors(errors: RoleFormErrors): boolean {
  return Object.keys(errors).length > 0;
}

/** Ids de los roles que cuelgan, directa o indirectamente, de `roleId`. */
export function descendantIds(roleId: number, roles: readonly RoleAdmin[]): Set<number> {
  const found = new Set<number>();
  const pending = [roleId];
  while (pending.length) {
    const current = pending.pop()!;
    for (const role of roles) {
      if (role.parent_role_id === current && !found.has(role.id)) {
        found.add(role.id);
        pending.push(role.id);
      }
    }
  }
  return found;
}

/** Posibles padres: roles activos, sin el propio ni sus descendientes (así no hay ciclo posible). */
export function parentOptions(roles: readonly RoleAdmin[], editingId: number | null): RoleAdmin[] {
  const blocked = editingId === null ? new Set<number>() : descendantIds(editingId, roles);
  return roles.filter((role) => role.is_active && role.id !== editingId && !blocked.has(role.id));
}

/** Por qué no se pueden editar los permisos propios de un rol; `null` si se pueden. */
export function lockedReason(role: RoleAdmin, actorRoleCodes: readonly string[]): string | null {
  if (role.code === ADMIN_CODE) {
    return 'El Administrador siempre tiene todos los permisos.';
  }
  if (!role.is_active) {
    return 'El rol está inactivo: actívalo para editar sus permisos.';
  }
  if (actorRoleCodes.includes(role.code)) {
    return 'No puedes cambiar los permisos de un rol que tú tienes.';
  }
  return null;
}

function ownSet(role: RoleAdmin, draft: Draft): ReadonlySet<string> {
  return draft.get(role.id) ?? new Set(role.own_permissions);
}

export type CellState = { kind: 'own' } | { kind: 'inherited'; from: string } | { kind: 'none' };

/** Estado de una celda de la matriz contando los cambios sin guardar (también los de los padres). */
export function resolveCell(role: RoleAdmin, code: string, roles: readonly RoleAdmin[], draft: Draft): CellState {
  if (ownSet(role, draft).has(code)) {
    return { kind: 'own' };
  }
  const byId = new Map(roles.map((item) => [item.id, item]));
  const seen = new Set<number>([role.id]);
  let parent = role.parent_role_id === null ? undefined : byId.get(role.parent_role_id);
  while (parent && !seen.has(parent.id) && parent.is_active) {
    if (ownSet(parent, draft).has(code)) {
      return { kind: 'inherited', from: parent.name };
    }
    seen.add(parent.id);
    parent = parent.parent_role_id === null ? undefined : byId.get(parent.parent_role_id);
  }
  return { kind: 'none' };
}

/** Marca o desmarca un permiso propio del rol; si queda igual a lo guardado, el rol sale del borrador. */
export function toggleDraft(draft: Draft, role: RoleAdmin, code: string): Draft {
  const next = new Set(ownSet(role, draft));
  if (next.has(code)) {
    next.delete(code);
  } else {
    next.add(code);
  }
  const result = new Map(draft);
  const saved = new Set(role.own_permissions);
  if (next.size === saved.size && [...next].every((item) => saved.has(item))) {
    result.delete(role.id);
  } else {
    result.set(role.id, next);
  }
  return result;
}

export interface DraftChange {
  role: RoleAdmin;
  added: string[];
  removed: string[];
}

export function draftChanges(draft: Draft, roles: readonly RoleAdmin[]): DraftChange[] {
  const changes: DraftChange[] = [];
  for (const role of roles) {
    const wanted = draft.get(role.id);
    if (!wanted) {
      continue;
    }
    const saved = new Set(role.own_permissions);
    const added = [...wanted].filter((code) => !saved.has(code)).sort();
    const removed = [...saved].filter((code) => !wanted.has(code)).sort();
    if (added.length || removed.length) {
      changes.push({ role, added, removed });
    }
  }
  return changes;
}

export interface RolePreview {
  /** Permisos que tendría quien solo tenga este rol (propios + heredados). */
  codes: string[];
  menu: NavItem[];
  /** Cuánto ve de cada recurso con datos por alcance. */
  scopes: { resource: string; label: string; scope: string }[];
}

const SCOPE_RESOURCES = ['tickets', 'solicitudes', 'dashboard', 'equipos'] as const;

/** Qué vería y qué podría hacer alguien con solo este rol, según lo guardado más los cambios sin guardar. */
export function previewRole(role: RoleAdmin, roles: readonly RoleAdmin[], matrix: readonly MatrixGroup[], draft: Draft): RolePreview {
  const codes = matrix
    .flatMap((group) => group.rows.map((row) => row.code))
    .filter((code) => resolveCell(role, code, roles, draft).kind !== 'none');
  const has = (code: string) => codes.includes(code);
  const scopes = SCOPE_RESOURCES.flatMap((resource) => {
    const scope = has(`${resource}:ver_todos`) ? 'Todo' : has(`${resource}:ver_asignados`) ? 'Lo asignado' : has(`${resource}:ver`) ? 'Lo propio' : '';
    return scope ? [{ resource, label: resourceLabel(resource), scope }] : [];
  });
  return { codes, menu: visibleNavItems(codes, [role.code]), scopes };
}

const SERVER_MESSAGES =
  /^(Ya existe un rol|Ese padre|La jerarquía|Los roles base|El rol |Este rol|No puedes (conceder|cambiar|asignar)|Permisos desconocidos|Rol no encontrado|Solo un administrador)/;

/** El servidor explica en español las reglas de roles: se muestran tal cual; lo demás, con el mensaje general. */
export function serverRoleMessage(detail: unknown): string | null {
  return typeof detail === 'string' && SERVER_MESSAGES.test(detail) ? detail : null;
}
