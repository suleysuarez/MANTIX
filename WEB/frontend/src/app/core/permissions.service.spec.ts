import { TestBed } from '@angular/core/testing';
import { BehaviorSubject, Subject } from 'rxjs';

import { ClerkState } from './clerk.types';
import { ClerkService } from './clerk.service';
import { LocalProfile, LocalProfileService } from './local-profile.service';
import { PermissionsService } from './permissions.service';

const profile = (codes: string[], roles = ['TECHNICIAN']): LocalProfile =>
  ({
    id: 1, email: 'a@x.com', full_name: 'Ana', employee_code: null, is_active: true,
    roles: roles.map((code) => ({ code, name: code })),
    permissions: codes.map((code) => ({ code, name: code })),
  }) as LocalProfile;

describe('PermissionsService', () => {
  let current: LocalProfile;
  let calls: number;
  const changes = new Subject<void>();
  const state$ = new BehaviorSubject<ClerkState>({ isSignedIn: true, user: null, session: null });

  beforeEach(() => {
    current = profile(['tickets:ver', 'tickets:cambiar_estado']);
    calls = 0;
    const fake = {
      changes,
      getProfile: async () => {
        calls += 1;
        return current;
      },
      can: async (code: string) => current.permissions.some((item) => item.code === code),
      clearQuietly: () => undefined,
    };
    TestBed.configureTestingModule({
      providers: [
        { provide: LocalProfileService, useValue: fake },
        { provide: ClerkService, useValue: { state$: state$.asObservable() } },
      ],
    });
  });

  it('reads the effective permissions once and answers right away afterwards', async () => {
    const service = TestBed.inject(PermissionsService);
    expect(service.loaded()).toBeFalse();
    expect(service.has('tickets:ver')).toBeFalse(); // nothing is granted before they are read

    await service.load();
    await service.load();

    expect(calls).toBe(1);
    expect(service.loaded()).toBeTrue();
    expect(service.has('tickets:ver')).toBeTrue();
    expect(service.has('usuarios:ver')).toBeFalse();
    expect(service.roles()).toEqual(['TECHNICIAN']);
  });

  it('answers any-of and all-of', async () => {
    const service = TestBed.inject(PermissionsService);
    await service.load();
    expect(service.hasAny(['usuarios:ver', 'tickets:ver'])).toBeTrue();
    expect(service.hasAny(['usuarios:ver'])).toBeFalse();
    expect(service.hasAll(['tickets:ver', 'tickets:cambiar_estado'])).toBeTrue();
    expect(service.hasAll(['tickets:ver', 'usuarios:ver'])).toBeFalse();
  });

  it('grants nothing when the server cannot be reached', async () => {
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [
        { provide: LocalProfileService, useValue: { changes, getProfile: () => Promise.reject(new Error('down')), can: () => Promise.reject(new Error('down')), clearQuietly: () => undefined } },
        { provide: ClerkService, useValue: { state$: state$.asObservable() } },
      ],
    });
    const service = TestBed.inject(PermissionsService);

    await service.load();

    expect(service.loaded()).toBeTrue(); // decided: hide, and the server decides anyway
    expect(service.has('tickets:ver')).toBeFalse();
    expect(await service.can('tickets:ver')).toBeFalse();
  });

  it('reads them again when the roles of the person change', async () => {
    const service = TestBed.inject(PermissionsService);
    await service.load();
    current = profile(['tickets:ver', 'tickets:asignar'], ['SUPERVISOR']);

    changes.next();
    await new Promise((resolve) => setTimeout(resolve));

    expect(service.has('tickets:asignar')).toBeTrue();
    expect(service.has('tickets:cambiar_estado')).toBeFalse();
    expect(service.roles()).toEqual(['SUPERVISOR']);
  });

  it('asks again on demand', async () => {
    const service = TestBed.inject(PermissionsService);
    await service.load();
    current = profile(['dashboard:ver']);
    await service.refresh();
    expect(service.has('dashboard:ver')).toBeTrue();
    expect(service.has('tickets:ver')).toBeFalse();
  });

  it('can() asks the server for one permission', async () => {
    const service = TestBed.inject(PermissionsService);
    expect(await service.can('tickets:ver')).toBeTrue();
    expect(await service.can('usuarios:ver')).toBeFalse();
  });
});
