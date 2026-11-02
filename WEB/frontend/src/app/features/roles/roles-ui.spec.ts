import { PermissionInfo } from '../../core/roles-admin.service';
import { PERMISSIONS, ROLES, role } from './roles-fixtures';
import {
  Draft,
  buildMatrix,
  descendantIds,
  draftChanges,
  lockedReason,
  parentOptions,
  previewRole,
  resolveCell,
  serverRoleMessage,
  toggleDraft,
  validateRoleForm,
} from './roles-ui';

const empty: Draft = new Map();

describe('buildMatrix', () => {
  it('groups by resource keeping the catalogue order and skips legacy permissions', () => {
    const legacy: PermissionInfo = { code: 'equipment.read', name: 'x', module: 'equipment', description: null, resource: null, action: null };
    const groups = buildMatrix([legacy, ...PERMISSIONS]);
    expect(groups.map((group) => group.label)).toEqual(['Tickets', 'Usuarios']);
    expect(groups[0].rows.map((row) => row.actionLabel)).toEqual(['ver', 'ver lo asignado', 'ver todo', 'asignar']);
  });
});

describe('resolveCell', () => {
  it('is own when the role grants it itself', () => {
    expect(resolveCell(ROLES[0], 'tickets:ver', ROLES, empty)).toEqual({ kind: 'own' });
  });

  it('is inherited from the nearest ancestor that grants it', () => {
    expect(resolveCell(ROLES[3], 'tickets:ver', ROLES, empty)).toEqual({ kind: 'inherited', from: 'Solicitante' });
    expect(resolveCell(ROLES[3], 'tickets:asignar', ROLES, empty)).toEqual({ kind: 'inherited', from: 'Supervisor' });
  });

  it('is none for a role outside the chain', () => {
    expect(resolveCell(ROLES[4], 'tickets:ver', ROLES, empty)).toEqual({ kind: 'none' });
  });

  it('follows unsaved changes of the parents too', () => {
    const draft = toggleDraft(empty, ROLES[0], 'tickets:ver');
    expect(resolveCell(ROLES[0], 'tickets:ver', ROLES, draft)).toEqual({ kind: 'none' });
    expect(resolveCell(ROLES[2], 'tickets:ver', ROLES, draft)).toEqual({ kind: 'none' });
  });

  it('does not inherit through an inactive ancestor and survives a corrupt cycle', () => {
    const roles = [ROLES[0], { ...ROLES[1], is_active: false }, ROLES[2]];
    expect(resolveCell(roles[2], 'tickets:ver', roles, empty)).toEqual({ kind: 'none' });
    const loop = [role(1, 'A', { parent_role_id: 2 }), role(2, 'B', { parent_role_id: 1 })];
    expect(resolveCell(loop[0], 'x', loop, empty)).toEqual({ kind: 'none' });
  });
});

describe('draft', () => {
  it('records a change and drops the role from the draft when it goes back to what is saved', () => {
    const changed = toggleDraft(empty, ROLES[4], 'tickets:ver');
    expect(changed.get(5)).toEqual(new Set(['tickets:ver']));
    const back = toggleDraft(changed, ROLES[4], 'tickets:ver');
    expect(back.has(5)).toBeFalse();
  });

  it('lists what each role gains and loses, sorted', () => {
    let draft = toggleDraft(empty, ROLES[4], 'tickets:ver');
    draft = toggleDraft(draft, ROLES[4], 'tickets:asignar');
    draft = toggleDraft(draft, ROLES[0], 'tickets:ver');
    const changes = draftChanges(draft, ROLES);
    expect(changes.map((change) => [change.role.code, change.added, change.removed])).toEqual([
      ['EMPLOYEE', [], ['tickets:ver']],
      ['COMPRAS', ['tickets:asignar', 'tickets:ver'], []],
    ]);
  });

  it('does not mutate the previous draft', () => {
    const first = toggleDraft(empty, ROLES[4], 'tickets:ver');
    toggleDraft(first, ROLES[4], 'tickets:asignar');
    expect(first.get(5)).toEqual(new Set(['tickets:ver']));
  });
});

describe('hierarchy helpers', () => {
  it('finds every descendant', () => {
    expect([...descendantIds(1, ROLES)].sort()).toEqual([2, 3, 4]);
    expect(descendantIds(5, ROLES).size).toBe(0);
  });

  it('offers as parent only active roles that are not the role or below it', () => {
    expect(parentOptions(ROLES, 2).map((item) => item.id)).toEqual([1, 5]);
    expect(parentOptions(ROLES, null).map((item) => item.id)).toEqual([1, 2, 3, 4, 5]);
    expect(parentOptions([...ROLES.slice(0, 4), { ...ROLES[4], is_active: false }], null).map((item) => item.id)).toEqual([1, 2, 3, 4]);
  });

  it('explains why a role cannot be edited', () => {
    expect(lockedReason(ROLES[3], [])).toContain('Administrador');
    expect(lockedReason({ ...ROLES[4], is_active: false }, [])).toContain('inactivo');
    expect(lockedReason(ROLES[2], ['SUPERVISOR'])).toContain('que tú tienes');
    expect(lockedReason(ROLES[2], ['ADMIN'])).toBeNull();
  });
});

describe('validateRoleForm', () => {
  const values = (name: string, description = '') => ({ name, description, parent_role_id: null });

  it('requires a name of a sensible length', () => {
    expect(validateRoleForm(values('  '), ROLES, null).name).toBe('Escribe el nombre del rol.');
    expect(validateRoleForm(values('ab'), ROLES, null).name).toContain('al menos 3');
    expect(validateRoleForm(values('x'.repeat(101)), ROLES, null).name).toContain('como máximo 100');
    expect(validateRoleForm(values('Auditoría'), ROLES, null)).toEqual({});
  });

  it('refuses a repeated name ignoring case, but not the role own name when editing', () => {
    expect(validateRoleForm(values('técnico'), ROLES, null).name).toBe('Ya existe un rol con ese nombre.');
    expect(validateRoleForm(values('Técnico'), ROLES, 2)).toEqual({});
  });

  it('limits the description', () => {
    expect(validateRoleForm(values('Nuevo', 'x'.repeat(501)), ROLES, null).description).toContain('como máximo 500');
  });
});

describe('previewRole', () => {
  const matrix = buildMatrix(PERMISSIONS);

  it('gathers own and inherited permissions, the menu and the data scope', () => {
    const preview = previewRole(ROLES[1], ROLES, matrix, empty);
    expect(preview.codes).toEqual(['tickets:ver', 'tickets:ver_asignados']);
    expect(preview.menu.map((item) => item.path)).toContain('/tickets');
    expect(preview.menu.map((item) => item.path)).not.toContain('/roles');
    expect(preview.scopes).toEqual([{ resource: 'tickets', label: 'Tickets', scope: 'Lo asignado' }]);
  });

  it('the widest scope wins and the administration entry follows the permission', () => {
    const admin = previewRole(ROLES[3], ROLES, matrix, empty);
    expect(admin.scopes[0].scope).toBe('Todo');
    expect(admin.menu.map((item) => item.path)).toContain('/roles');
  });

  it('a role with nothing sees only the dashboard', () => {
    const none = previewRole(ROLES[4], ROLES, matrix, empty);
    expect(none.codes).toEqual([]);
    expect(none.menu.map((item) => item.path)).toEqual(['/dashboard']);
    expect(none.scopes).toEqual([]);
  });

  it('reflects unsaved changes', () => {
    const draft = toggleDraft(empty, ROLES[4], 'tickets:ver_todos');
    expect(previewRole(ROLES[4], ROLES, matrix, draft).scopes[0].scope).toBe('Todo');
  });
});

describe('serverRoleMessage', () => {
  it('passes the role rules the server already explains in Spanish', () => {
    expect(serverRoleMessage('Ya existe un rol llamado «Compras».')).toContain('Compras');
    expect(serverRoleMessage('Este rol tiene usuarios asignados. Reasígnalos antes de eliminarlo.')).toContain('usuarios');
  });

  it('ignores anything else', () => {
    expect(serverRoleMessage('internal server error')).toBeNull();
    expect(serverRoleMessage(undefined)).toBeNull();
  });
});
