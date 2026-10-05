import { visibleNavItems } from './nav-items';

describe('visibleNavItems', () => {
  it('always shows the dashboard', () => {
    expect(visibleNavItems([]).map((item) => item.path)).toEqual(['/dashboard']);
  });

  it('adds only the sections the user has permission for', () => {
    expect(visibleNavItems(['equipment.read']).map((item) => item.path)).toEqual(['/dashboard', '/equipos', '/inventario']);
  });

  it('shows administration only with users.manage', () => {
    const paths = visibleNavItems(['equipment.read', 'users.manage']).map((item) => item.path);
    expect(paths).toContain('/admin/pending-users');
  });
});
