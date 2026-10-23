import { ComponentFixture, TestBed } from '@angular/core/testing';
import { BehaviorSubject, of } from 'rxjs';

import { ClerkService } from '../../core/clerk.service';
import { HistoryEntry, ProfileData, ProfileService } from '../../core/profile.service';
import { ProfileState, ProfileStore } from '../../core/profile.store';
import { ProfileComponent } from './profile.component';

const profile = (over: Partial<ProfileData> = {}): ProfileData => ({
  id: 1, email: 'ana@x.com', full_name: 'Ana Pérez', phone: null, employee_code: 'EMP-1',
  roles: [{ code: 'EMPLOYEE', name: 'Empleado' }], has_avatar: false, avatar_version: null,
  last_login_at: '2026-10-14T10:00:00Z',
  created_at: '2026-01-01T00:00:00Z', ...over,
});

const entry = (id: number, action: string, kind: HistoryEntry['kind'], actor: string | null = null): HistoryEntry => ({
  id, action, kind, entity_type: 'user', entity_id: 1, actor_name: actor, ip_address: '203.0.113.7', created_at: '2026-10-14T10:00:00Z',
});

describe('ProfileComponent', () => {
  let fixture: ComponentFixture<ProfileComponent>;
  let store: jasmine.SpyObj<ProfileStore>;
  let api: jasmine.SpyObj<ProfileService>;
  let subject: BehaviorSubject<ProfileState>;
  const root = () => fixture.nativeElement as HTMLElement;
  const text = () => root().textContent!.replace(/\s+/g, ' ');
  const tab = (label: string) =>
    Array.from(root().querySelectorAll('[role="tab"]')).find((t) => t.textContent!.includes(label)) as HTMLButtonElement;

  async function create(data: ProfileData = profile(), avatarUrl: string | null = null): Promise<void> {
    subject = new BehaviorSubject<ProfileState>({ profile: data, avatarUrl, loading: false, error: '', busy: false });
    store = Object.assign(jasmine.createSpyObj('ProfileStore', ['load', 'update', 'uploadAvatar', 'removeAvatar', 'changePassword']), {
      state$: subject.asObservable(),
    }) as unknown as jasmine.SpyObj<ProfileStore>;
    store.update.and.returnValue(of({ ok: true, fieldErrors: {} }));
    store.removeAvatar.and.returnValue(of({ ok: true, fieldErrors: {} }));
    api = jasmine.createSpyObj('ProfileService', ['history']);
    api.history.and.returnValue(of({ items: [entry(1, 'auth.login', 'session'), entry(2, 'roles.replaced', 'security', 'Admin Uno')], total: 2 }));
    TestBed.configureTestingModule({
      providers: [
        { provide: ProfileStore, useValue: store },
        { provide: ProfileService, useValue: api },
        { provide: ClerkService, useValue: { getActiveSessions: () => Promise.resolve({ sessions: [], currentId: null }), revokeSession: () => Promise.resolve() } },
      ],
    });
    fixture = TestBed.createComponent(ProfileComponent);
    document.body.appendChild(root());
    fixture.detectChanges();
    await fixture.whenStable();
    fixture.detectChanges();
  }

  afterEach(() => root().remove());

  it('shows who the person is, with initials when there is no photo', async () => {
    await create();

    expect(store.load).toHaveBeenCalled();
    expect(text()).toContain('Ana Pérez');
    expect(text()).toContain('Empleado');
    expect(text()).toContain('Código EMP-1');
    expect(text()).toContain('AP');
    expect(root().querySelector('header img')).toBeNull();
  });

  it('shows the photo when there is one', async () => {
    await create(profile({ has_avatar: true, avatar_version: 3 }), 'blob:foto');

    expect(root().querySelector('header img')?.getAttribute('src')).toBe('blob:foto');
    expect(text()).toContain('Cambiar foto');
    expect(text()).toContain('Quitar foto');
  });

  it('keeps the e-mail and the employee code locked', async () => {
    await create();

    const email = root().querySelector('#pf-email') as HTMLInputElement;
    const code = root().querySelector('#pf-code') as HTMLInputElement;
    expect(email.disabled).toBeTrue();
    expect(email.value).toBe('ana@x.com');
    expect(code.disabled).toBeTrue();
    expect(text()).toContain('no se puede cambiar');
  });

  it('saves only after a change and trims the text', async () => {
    await create();
    const save = () => Array.from(root().querySelectorAll('button[type="submit"]')).find((b) => b.textContent!.includes('Guardar')) as HTMLButtonElement;
    expect(save().disabled).toBeTrue();

    const name = root().querySelector('#pf-name') as HTMLInputElement;
    name.value = '  Ana   María  ';
    name.dispatchEvent(new Event('input'));
    fixture.detectChanges();
    expect(save().disabled).toBeFalse();
    (root().querySelector('form') as HTMLFormElement).dispatchEvent(new Event('submit'));

    expect(store.update).toHaveBeenCalledWith({ full_name: 'Ana María', phone: null });
  });

  it('shows the message under the field and does not send an invalid form', async () => {
    await create();
    const name = root().querySelector('#pf-name') as HTMLInputElement;
    name.value = 'A';
    name.dispatchEvent(new Event('input'));
    fixture.detectChanges();

    (root().querySelector('form') as HTMLFormElement).dispatchEvent(new Event('submit'));
    fixture.detectChanges();

    expect(store.update).not.toHaveBeenCalled();
    expect(root().querySelector('#pf-name-err')?.textContent).toContain('al menos 2');
    expect(root().querySelector('#pf-name')?.getAttribute('aria-invalid')).toBe('true');
  });

  it('moves between tabs with the arrow keys', async () => {
    await create();

    tab('Mis datos').dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }));
    fixture.detectChanges();

    expect(tab('Seguridad').getAttribute('aria-selected')).toBe('true');
    expect(tab('Mis datos').getAttribute('tabindex')).toBe('-1');
  });

  it('has no preferences tab', async () => {
    await create();

    expect(Array.from(root().querySelectorAll('[role="tab"]')).map((t) => t.textContent!.trim())).toEqual(['personMis datos', 'shield_lockSeguridad', 'historyHistorial']);
  });

  it('shows the password form and the sessions in the security tab', async () => {
    await create();
    tab('Seguridad').click();
    fixture.detectChanges();
    await fixture.whenStable();
    fixture.detectChanges();

    expect(text()).toContain('Cambiar contraseña');
    expect(text()).toContain('Sesiones activas');
  });

  it('lists the history with who did what, and filters on the server', async () => {
    await create();
    tab('Historial').click();
    fixture.detectChanges();

    expect(text()).toContain('Iniciaste sesión');
    expect(text()).toContain('Tus roles fueron actualizados');
    expect(text()).toContain('Por Admin Uno');
    expect(text()).toContain('IP 203.0.113.7');
    expect(api.history).toHaveBeenCalledWith(jasmine.objectContaining({ page: 1, size: 15 }));

    const select = root().querySelector('#ph-kind') as HTMLSelectElement;
    select.value = 'security';
    select.dispatchEvent(new Event('change'));
    expect(api.history.calls.mostRecent().args[0]).toEqual(jasmine.objectContaining({ kind: 'security', page: 1 }));
  });
});
