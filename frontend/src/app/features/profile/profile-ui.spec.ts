import { actionInfo, avatarFileError, avatarSizeError, byText, newPasswordError, validateProfile } from './profile-ui';

describe('validateProfile', () => {
  it('accepts a valid name with or without phone', () => {
    expect(validateProfile({ full_name: 'Ana Pérez', phone: '' })).toEqual({});
    expect(validateProfile({ full_name: 'Ana Pérez', phone: '+57 300 123 4567' })).toEqual({});
  });

  it('asks for the name and keeps its limits', () => {
    expect(validateProfile({ full_name: '   ', phone: '' }).full_name).toBe('El nombre es obligatorio.');
    expect(validateProfile({ full_name: 'A', phone: '' }).full_name).toContain('al menos 2');
    expect(validateProfile({ full_name: 'A'.repeat(121), phone: '' }).full_name).toContain('120');
  });

  it('checks the phone format only when filled', () => {
    expect(validateProfile({ full_name: 'Ana Pérez', phone: 'abc' }).phone).toContain('teléfono');
    expect(validateProfile({ full_name: 'Ana Pérez', phone: '12' }).phone).toContain('teléfono');
  });
});

describe('avatar checks', () => {
  it('accepts PNG and JPEG up to 2 MB', () => {
    expect(avatarFileError({ type: 'image/png', size: 1000 })).toBe('');
    expect(avatarFileError({ type: 'image/jpeg', size: 2 * 1024 * 1024 })).toBe('');
  });

  it('refuses other types, heavy and empty files', () => {
    expect(avatarFileError({ type: 'image/gif', size: 1000 })).toContain('PNG o un JPG');
    expect(avatarFileError({ type: 'application/pdf', size: 1000 })).toContain('PNG o un JPG');
    expect(avatarFileError({ type: 'image/png', size: 2 * 1024 * 1024 + 1 })).toContain('2 MB');
    expect(avatarFileError({ type: 'image/png', size: 0 })).toContain('vacío');
  });

  it('refuses a photo whose short side is under 64 px', () => {
    expect(avatarSizeError(64, 64)).toBe('');
    expect(avatarSizeError(500, 63)).toContain('64×64');
  });
});

describe('newPasswordError', () => {
  it('walks the policy in order', () => {
    expect(newPasswordError('x', '', '')).toContain('Escribe');
    expect(newPasswordError('x', 'Corta1A', 'Corta1A')).toContain('al menos 10');
    expect(newPasswordError('x', 'tiene espacio 1Aa', 'tiene espacio 1Aa')).toContain('espacios');
    expect(newPasswordError('x', 'sinmayuscula123', 'sinmayuscula123')).toContain('mayúsculas');
    expect(newPasswordError('Segura12345', 'Segura12345', 'Segura12345')).toContain('distinta');
    expect(newPasswordError('Actual-2026', 'Segura12345', 'Otra12345678')).toContain('no coinciden');
  });

  it('accepts a strong, confirmed and different password', () => {
    expect(newPasswordError('Actual-2026', 'Segura12345', 'Segura12345')).toBe('');
  });
});

describe('history texts', () => {
  it('names the known actions in plain Spanish', () => {
    expect(actionInfo({ action: 'auth.login' }).label).toBe('Iniciaste sesión');
    expect(actionInfo({ action: 'profile.password_changed' }).label).toBe('Cambiaste tu contraseña');
    expect(actionInfo({ action: 'roles.replaced' }).label).toBe('Tus roles fueron actualizados');
  });

  it('never shows a raw technical key for an unknown action', () => {
    expect(actionInfo({ action: 'maintenance.status_changed' }).label).toBe('Actividad registrada');
  });

  it('says who did it only when it was somebody else', () => {
    expect(byText({ actor_name: 'Admin Uno' })).toBe('Por Admin Uno');
    expect(byText({ actor_name: null })).toBe('');
  });
});
