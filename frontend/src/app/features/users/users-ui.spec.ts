import { ManagedAccount } from '../../core/users.service';
import { accessState, hasErrors, lastAccessText, passwordError, roleNames, validateUserForm } from './users-ui';

const valid = { full_name: 'Ana Pérez', email: 'ana@empresa.com', phone: '', employee_code: '', role_ids: [2] };

describe('validateUserForm', () => {
  it('accepts a complete form', () => {
    expect(hasErrors(validateUserForm(valid, true))).toBeFalse();
  });

  it('asks for the name, with its length limits', () => {
    expect(validateUserForm({ ...valid, full_name: '   ' }, true).full_name).toBe('El nombre es obligatorio.');
    expect(validateUserForm({ ...valid, full_name: 'A' }, true).full_name).toContain('al menos 2');
    expect(validateUserForm({ ...valid, full_name: 'A'.repeat(121) }, true).full_name).toContain('120');
  });

  it('checks the e-mail format', () => {
    expect(validateUserForm({ ...valid, email: '' }, true).email).toBe('El correo es obligatorio.');
    expect(validateUserForm({ ...valid, email: 'no-es-correo' }, true).email).toContain('correo válido');
    expect(validateUserForm({ ...valid, email: 'a@b' }, true).email).toContain('correo válido');
  });

  it('checks the optional phone and employee code only when filled', () => {
    expect(validateUserForm({ ...valid, phone: 'abc' }, true).phone).toContain('teléfono');
    expect(validateUserForm({ ...valid, phone: '+57 300 123 4567' }, true).phone).toBeUndefined();
    expect(validateUserForm({ ...valid, employee_code: '!!' }, true).employee_code).toContain('código');
    expect(validateUserForm({ ...valid, employee_code: 'EMP-014' }, true).employee_code).toBeUndefined();
  });

  it('requires a role only when asked to', () => {
    expect(validateUserForm({ ...valid, role_ids: [] }, true).role_ids).toBe('Elige al menos un rol.');
    expect(validateUserForm({ ...valid, role_ids: [] }, false).role_ids).toBeUndefined();
  });
});

describe('passwordError', () => {
  it('walks the policy in order', () => {
    expect(passwordError('', '')).toContain('Escribe');
    expect(passwordError('Corta1A', 'Corta1A')).toContain('al menos 10');
    expect(passwordError('tiene espacio 1Aa', 'tiene espacio 1Aa')).toContain('espacios');
    expect(passwordError('sinmayuscula123', 'sinmayuscula123')).toContain('mayúsculas');
    expect(passwordError('SINMINUSCULA123', 'SINMINUSCULA123')).toContain('minúsculas');
    expect(passwordError('SinNumeroAbcdef', 'SinNumeroAbcdef')).toContain('números');
    expect(passwordError('Segura12345', 'Otra12345678')).toContain('no coinciden');
  });

  it('accepts a strong password that is confirmed', () => {
    expect(passwordError('Segura12345', 'Segura12345')).toBe('');
  });
});

describe('accessState and texts', () => {
  const user = (over: Partial<ManagedAccount>): ManagedAccount => ({
    id: 1, email: 'a@x.com', full_name: 'A', phone: null, employee_code: null, is_active: true, roles: [],
    created_at: '2026-01-01T00:00:00Z', last_login_at: null, linked: false, ...over,
  });

  it('puts inactive first, then never signed in', () => {
    expect(accessState(user({ is_active: false, last_login_at: '2026-01-02T00:00:00Z' }))).toBe('inactive');
    expect(accessState(user({}))).toBe('never');
    expect(accessState(user({ last_login_at: '2026-01-02T00:00:00Z' }))).toBe('active');
  });

  it('describes the last access in relative terms', () => {
    const now = new Date('2026-10-15T12:00:00Z');
    expect(lastAccessText(null, now)).toBe('Nunca');
    expect(lastAccessText('2026-10-15T11:59:50Z', now)).toBe('Ahora mismo');
    expect(lastAccessText('2026-10-15T11:30:00Z', now)).toBe('Hace 30 min');
    expect(lastAccessText('2026-10-15T09:00:00Z', now)).toBe('Hace 3 h');
    expect(lastAccessText('2026-10-14T09:00:00Z', now)).toBe('Hace 1 día');
  });

  it('names the roles or says there are none', () => {
    expect(roleNames({ roles: [] })).toBe('Sin rol');
    expect(roleNames({ roles: [{ id: 1, code: 'ADMIN', name: 'Administrador' }, { id: 2, code: 'EMPLOYEE', name: 'Empleado' }] })).toBe('Administrador, Empleado');
  });
});
