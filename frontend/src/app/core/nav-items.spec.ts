import { visibleNavItems } from './nav-items';

describe('visibleNavItems', () => {
  it('always shows the dashboard', () => {
    expect(visibleNavItems([]).map((item) => item.path)).toEqual(['/dashboard']);
  });

  it('adds only the sections the user has permission for', () => {
    expect(visibleNavItems(['equipos:ver']).map((item) => item.path)).toEqual(['/dashboard', '/equipos']);
    expect(visibleNavItems(['inventario:ver']).map((item) => item.path)).toEqual(['/dashboard', '/inventario']);
  });

  it('shows administration only with the users permissions', () => {
    const paths = visibleNavItems(['equipos:ver', 'usuarios:ver', 'usuarios:asignar']).map((item) => item.path);
    expect(paths).toContain('/admin/pending-users');
    expect(paths).toContain('/usuarios');
  });

  it('hides the users screen from whoever cannot manage users', () => {
    expect(visibleNavItems(['equipos:ver', 'tickets:ver', 'mantenimiento:ver']).map((item) => item.path)).not.toContain('/usuarios');
  });
});

describe('visibleNavItems by permission (never by role name)', () => {
  it('shows the pending-requests queue to whoever can see every request', () => {
    expect(visibleNavItems(['tickets:ver', 'solicitudes:ver_todos']).map((item) => item.path)).toContain('/solicitudes');
  });

  it('hides it from a technician, who only sees what is assigned to them', () => {
    expect(visibleNavItems(['tickets:ver', 'tickets:ver_asignados'], ['TECHNICIAN']).map((item) => item.path)).not.toContain('/solicitudes');
  });

  it('works the same for a custom role: the permission decides, not the name', () => {
    expect(visibleNavItems(['solicitudes:ver_todos'], ['MI_ROL']).map((item) => item.path)).toContain('/solicitudes');
    expect(visibleNavItems([], ['SUPERVISOR']).map((item) => item.path)).not.toContain('/solicitudes');
  });
});

describe('visibleNavItems: roles and permissions screen', () => {
  it('is only for whoever may assign roles', () => {
    expect(visibleNavItems(['usuarios:ver', 'usuarios:editar']).map((item) => item.path)).not.toContain('/roles');
    expect(visibleNavItems(['usuarios:asignar']).map((item) => item.path)).toContain('/roles');
  });
});
