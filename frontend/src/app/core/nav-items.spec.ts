import { visibleNavItems } from './nav-items';

describe('visibleNavItems', () => {
  it('always shows the dashboard', () => {
    expect(visibleNavItems([]).map((item) => item.path)).toEqual(['/dashboard']);
  });

  it('adds only the sections the user has permission for', () => {
    expect(visibleNavItems(['equipment.read']).map((item) => item.path)).toEqual(['/dashboard', '/equipos']);
    expect(visibleNavItems(['inventory.read']).map((item) => item.path)).toEqual(['/dashboard', '/inventario']);
  });

  it('shows administration only with users.manage', () => {
    const paths = visibleNavItems(['equipment.read', 'users.manage']).map((item) => item.path);
    expect(paths).toContain('/admin/pending-users');
  });
});

describe('visibleNavItems by role', () => {
  const manage = ['maintenance.read', 'maintenance.manage'];

  it('shows the pending-requests queue only to administrators and supervisors', () => {
    expect(visibleNavItems(manage, ['SUPERVISOR']).map((item) => item.path)).toContain('/solicitudes');
    expect(visibleNavItems(manage, ['ADMIN']).map((item) => item.path)).toContain('/solicitudes');
  });

  it('hides it from a technician even though they hold maintenance.manage', () => {
    expect(visibleNavItems(manage, ['TECHNICIAN']).map((item) => item.path)).not.toContain('/solicitudes');
    expect(visibleNavItems(manage).map((item) => item.path)).not.toContain('/solicitudes');
  });

  it('still needs the permission, not just the role', () => {
    expect(visibleNavItems(['maintenance.read'], ['SUPERVISOR']).map((item) => item.path)).not.toContain('/solicitudes');
  });
});
