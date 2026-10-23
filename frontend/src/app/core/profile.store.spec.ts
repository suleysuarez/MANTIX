import { HttpErrorResponse } from '@angular/common/http';
import { TestBed } from '@angular/core/testing';
import { of, throwError } from 'rxjs';

import { LocalProfileService } from './local-profile.service';
import { ProfileData, ProfileService } from './profile.service';
import { ProfileState, ProfileStore } from './profile.store';
import { ToastService } from './toast.service';

const profile = (over: Partial<ProfileData> = {}): ProfileData => ({
  id: 1, email: 'ana@x.com', full_name: 'Ana Pérez', phone: null, employee_code: null, roles: [],
  has_avatar: false, avatar_version: null,
  last_login_at: null, created_at: '2026-01-01T00:00:00Z', ...over,
});

describe('ProfileStore', () => {
  let api: jasmine.SpyObj<ProfileService>;
  let toasts: jasmine.SpyObj<ToastService>;
  let local: jasmine.SpyObj<LocalProfileService>;
  let store: ProfileStore;
  let latest: ProfileState;

  beforeEach(() => {
    api = jasmine.createSpyObj('ProfileService', ['get', 'update', 'uploadAvatar', 'avatar', 'removeAvatar', 'changePassword']);
    toasts = jasmine.createSpyObj('ToastService', ['success', 'error']);
    local = jasmine.createSpyObj('LocalProfileService', ['setName']);
    spyOn(URL, 'createObjectURL').and.returnValue('blob:foto-1');
    spyOn(URL, 'revokeObjectURL');
    TestBed.configureTestingModule({
      providers: [ProfileStore, { provide: ProfileService, useValue: api }, { provide: ToastService, useValue: toasts }, { provide: LocalProfileService, useValue: local }],
    });
    store = TestBed.inject(ProfileStore);
    store.state$.subscribe((state) => (latest = state));
  });

  it('loads the profile', () => {
    api.get.and.returnValue(of(profile()));

    store.load();

    expect(latest.profile?.full_name).toBe('Ana Pérez');
    expect(latest.avatarUrl).toBeNull();
    expect(latest.loading).toBeFalse();
    expect(api.avatar).not.toHaveBeenCalled();
  });

  it('reports a failure to load', () => {
    api.get.and.returnValue(throwError(() => new Error('boom')));

    store.load();

    expect(latest.error).toBe('No se pudo cargar tu perfil.');
    expect(latest.loading).toBeFalse();
  });

  it('fetches the photo when there is one', () => {
    api.get.and.returnValue(of(profile({ has_avatar: true, avatar_version: 5 })));
    api.avatar.and.returnValue(of(new Blob(['x'])));

    store.load();

    expect(latest.avatarUrl).toBe('blob:foto-1');
  });

  it('shows the new name everywhere after saving and says so', () => {
    api.get.and.returnValue(of(profile()));
    store.load();
    api.update.and.returnValue(of(profile({ full_name: 'Ana María' })));
    let ok = false;

    store.update({ full_name: 'Ana María' }).subscribe((r) => (ok = r.ok));

    expect(ok).toBeTrue();
    expect(latest.profile?.full_name).toBe('Ana María');
    expect(toasts.success).toHaveBeenCalledWith('Datos actualizados.');
    expect(latest.busy).toBeFalse();
  });

  it('keeps the cached profile of other screens in sync with the new name', () => {
    api.get.and.returnValue(of(profile()));
    store.load();
    api.update.and.returnValue(of(profile({ full_name: 'Ana María' })));

    store.update({ full_name: 'Ana María' }).subscribe();

    expect(local.setName).toHaveBeenCalledWith('Ana María');
  });

  it('replaces the photo only when its version changes and frees the old one', () => {
    api.get.and.returnValue(of(profile({ has_avatar: true, avatar_version: 1 })));
    api.avatar.and.returnValue(of(new Blob(['x'])));
    store.load();
    (URL.createObjectURL as jasmine.Spy).and.returnValue('blob:foto-2');
    api.uploadAvatar.and.returnValue(of(profile({ has_avatar: true, avatar_version: 2 })));

    store.uploadAvatar(new File(['x'], 'yo.png', { type: 'image/png' })).subscribe();

    expect(latest.avatarUrl).toBe('blob:foto-2');
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:foto-1');
  });

  it('goes back to the initials when the photo is removed', () => {
    api.get.and.returnValue(of(profile({ has_avatar: true, avatar_version: 1 })));
    api.avatar.and.returnValue(of(new Blob(['x'])));
    store.load();
    api.removeAvatar.and.returnValue(of(profile()));

    store.removeAvatar().subscribe();

    expect(latest.avatarUrl).toBeNull();
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:foto-1');
  });

  it('turns a refusal into a Spanish toast and keeps the data', () => {
    api.get.and.returnValue(of(profile()));
    store.load();
    api.update.and.returnValue(throwError(() => new HttpErrorResponse({ status: 403, error: { detail: 'tu correo no se puede modificar desde el perfil' } })));
    let ok = true;

    store.update({ full_name: 'Otro Nombre' }).subscribe((r) => (ok = r.ok));

    expect(ok).toBeFalse();
    expect(toasts.error).toHaveBeenCalledWith('Tu correo es tu identidad de acceso y no se puede modificar desde el perfil.');
    expect(latest.profile?.full_name).toBe('Ana Pérez');
  });

  it('sends the password to the server and keeps it out of the state', () => {
    api.get.and.returnValue(of(profile()));
    store.load();
    api.changePassword.and.returnValue(of(undefined));

    store.changePassword('Actual-2026', 'Nueva-2026-Segura').subscribe();

    expect(api.changePassword).toHaveBeenCalledWith('Actual-2026', 'Nueva-2026-Segura');
    expect(JSON.stringify(latest)).not.toContain('Nueva-2026');
    expect(toasts.success).toHaveBeenCalledWith('Contraseña cambiada.');
  });

  it('explains a wrong current password', () => {
    api.get.and.returnValue(of(profile()));
    store.load();
    api.changePassword.and.returnValue(throwError(() => new HttpErrorResponse({ status: 422, error: { detail: 'la contraseña actual no es correcta' } })));

    store.changePassword('Mala-2026-abc', 'Nueva-2026-Segura').subscribe();

    expect(toasts.error).toHaveBeenCalledWith('La contraseña actual no es correcta.');
  });
});
