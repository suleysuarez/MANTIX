import { HttpRequest, HttpResponse } from '@angular/common/http';
import { TestBed } from '@angular/core/testing';
import { Router } from '@angular/router';
import { of } from 'rxjs';

import { authGuard, authorizedGuard, guestGuard, permissionGuard, roleGuard } from './auth.guard';
import { authInterceptor } from './auth.interceptor';
import { ClerkService } from './clerk.service';
import { LocalProfileService } from './local-profile.service';

function runGuard(): Promise<unknown> {
  return TestBed.runInInjectionContext(() =>
    authGuard({} as never, {} as never),
  ) as Promise<unknown>;
}

function runAuthorizedGuard(): Promise<unknown> {
  return TestBed.runInInjectionContext(() =>
    authorizedGuard({} as never, {} as never),
  ) as Promise<unknown>;
}

function runPermissionGuard(): Promise<unknown> {
  return TestBed.runInInjectionContext(() =>
    permissionGuard('users.manage')({} as never, {} as never),
  ) as Promise<unknown>;
}

describe('Clerk auth guard', () => {
  it('allows an authenticated Clerk session', async () => {
    TestBed.configureTestingModule({
      providers: [
        { provide: ClerkService, useValue: { initialize: jasmine.createSpy().and.resolveTo(), isSignedIn: true } },
        { provide: Router, useValue: { createUrlTree: jasmine.createSpy() } },
      ],
    });
    expect(await runGuard()).toBeTrue();
  });

  it('redirects unauthenticated users to the public login route', async () => {
    const createUrlTree = jasmine.createSpy('createUrlTree').and.returnValue('/auth/login');
    TestBed.configureTestingModule({
      providers: [
        { provide: ClerkService, useValue: { initialize: jasmine.createSpy().and.resolveTo(), isSignedIn: false } },
        { provide: Router, useValue: { createUrlTree } },
      ],
    });
    await runGuard();
    expect(createUrlTree).toHaveBeenCalledWith(['/auth/login']);
  });
});

describe('local authorization guard', () => {
  it('allows a Clerk user with a local application role', async () => {
    TestBed.configureTestingModule({
      providers: [
        { provide: ClerkService, useValue: { initialize: jasmine.createSpy().and.resolveTo(), isSignedIn: true } },
        { provide: LocalProfileService, useValue: { getProfile: jasmine.createSpy().and.resolveTo({ roles: [{ code: 'ADMIN' }] }) } },
        { provide: Router, useValue: { createUrlTree: jasmine.createSpy() } },
      ],
    });
    expect(await runAuthorizedGuard()).toBeTrue();
  });

  it('redirects an authenticated user without roles to pending authorization', async () => {
    const createUrlTree = jasmine.createSpy('createUrlTree').and.returnValue('/auth/pending');
    TestBed.configureTestingModule({
      providers: [
        { provide: ClerkService, useValue: { initialize: jasmine.createSpy().and.resolveTo(), isSignedIn: true } },
        { provide: LocalProfileService, useValue: { getProfile: jasmine.createSpy().and.resolveTo({ roles: [] }) } },
        { provide: Router, useValue: { createUrlTree } },
      ],
    });
    await runAuthorizedGuard();
    expect(createUrlTree).toHaveBeenCalledWith(['/auth/pending']);
  });
});

describe('guards when the API is unreachable', () => {
  function setup(createUrlTree: jasmine.Spy): void {
    TestBed.configureTestingModule({
      providers: [
        { provide: ClerkService, useValue: { initialize: jasmine.createSpy().and.resolveTo(), isSignedIn: true } },
        { provide: LocalProfileService, useValue: { getProfile: jasmine.createSpy().and.rejectWith(new Error('offline')) } },
        { provide: Router, useValue: { createUrlTree } },
      ],
    });
  }

  it('sends authorizedGuard to the unavailable screen', async () => {
    const createUrlTree = jasmine.createSpy('createUrlTree').and.returnValue('/auth/unavailable');
    setup(createUrlTree);
    await runAuthorizedGuard();
    expect(createUrlTree).toHaveBeenCalledWith(['/auth/unavailable']);
  });

  it('sends permissionGuard to the unavailable screen', async () => {
    const createUrlTree = jasmine.createSpy('createUrlTree').and.returnValue('/auth/unavailable');
    setup(createUrlTree);
    await runPermissionGuard();
    expect(createUrlTree).toHaveBeenCalledWith(['/auth/unavailable']);
  });
});

describe('permission guard', () => {
  it('allows a user with users.manage permission', async () => {
    TestBed.configureTestingModule({
      providers: [
        { provide: ClerkService, useValue: { initialize: jasmine.createSpy().and.resolveTo(), isSignedIn: true } },
        { provide: LocalProfileService, useValue: { getProfile: jasmine.createSpy().and.resolveTo({ permissions: [{ code: 'users.manage' }] }) } },
        { provide: Router, useValue: { createUrlTree: jasmine.createSpy() } },
      ],
    });
    expect(await runPermissionGuard()).toBeTrue();
  });

  it('redirects a signed-in user without users.manage permission', async () => {
    const createUrlTree = jasmine.createSpy('createUrlTree').and.returnValue('/auth/pending');
    TestBed.configureTestingModule({
      providers: [
        { provide: ClerkService, useValue: { initialize: jasmine.createSpy().and.resolveTo(), isSignedIn: true } },
        { provide: LocalProfileService, useValue: { getProfile: jasmine.createSpy().and.resolveTo({ permissions: [] }) } },
        { provide: Router, useValue: { createUrlTree } },
      ],
    });
    await runPermissionGuard();
    expect(createUrlTree).toHaveBeenCalledWith(['/auth/pending']);
  });
});

describe('Clerk auth interceptor', () => {
  it('attaches only the Clerk session token to FastAPI requests', (done) => {
    TestBed.configureTestingModule({
      providers: [{ provide: ClerkService, useValue: { getToken: jasmine.createSpy().and.resolveTo('clerk-token') } }],
    });
    const request = new HttpRequest('GET', 'http://localhost:8000/auth/me');
    TestBed.runInInjectionContext(() =>
      authInterceptor(request, (authorized) => {
        expect(authorized.headers.get('Authorization')).toBe('Bearer clerk-token');
        done();
        return of(new HttpResponse({ status: 200, body: {} }));
      }),
    ).subscribe();
  });
});

describe('guest guard', () => {
  it('lets a signed-out user reach /auth/login', async () => {
    TestBed.configureTestingModule({
      providers: [
        { provide: ClerkService, useValue: { initialize: jasmine.createSpy().and.resolveTo(), isSignedIn: false } },
        { provide: Router, useValue: { createUrlTree: jasmine.createSpy() } },
      ],
    });
    expect(await TestBed.runInInjectionContext(() => guestGuard({} as never, {} as never))).toBeTrue();
  });

  it('redirects a signed-in user away from /auth/login', async () => {
    const createUrlTree = jasmine.createSpy('createUrlTree').and.returnValue('/dashboard');
    TestBed.configureTestingModule({
      providers: [
        { provide: ClerkService, useValue: { initialize: jasmine.createSpy().and.resolveTo(), isSignedIn: true } },
        { provide: Router, useValue: { createUrlTree } },
      ],
    });
    await TestBed.runInInjectionContext(() => guestGuard({} as never, {} as never));
    expect(createUrlTree).toHaveBeenCalledWith(['/dashboard']);
  });
});

describe('403 instead of silence', () => {
  function setup(createUrlTree: jasmine.Spy, profile: unknown): void {
    TestBed.configureTestingModule({
      providers: [
        { provide: ClerkService, useValue: { initialize: jasmine.createSpy().and.resolveTo(), isSignedIn: true } },
        { provide: LocalProfileService, useValue: { getProfile: jasmine.createSpy().and.resolveTo(profile) } },
        { provide: Router, useValue: { createUrlTree } },
      ],
    });
  }

  const runRole = () =>
    TestBed.runInInjectionContext(() => roleGuard('maintenance.manage', 'ADMIN', 'SUPERVISOR')({} as never, {} as never));

  it('sends a user with a role but without the permission to the 403 page', async () => {
    const createUrlTree = jasmine.createSpy('createUrlTree').and.returnValue('/acceso-denegado');
    setup(createUrlTree, { roles: [{ code: 'TECHNICIAN' }], permissions: [] });
    await runPermissionGuard();
    expect(createUrlTree).toHaveBeenCalledWith(['/acceso-denegado']);
  });

  it('sends a user with the permission but the wrong role to the 403 page', async () => {
    const createUrlTree = jasmine.createSpy('createUrlTree').and.returnValue('/acceso-denegado');
    setup(createUrlTree, { roles: [{ code: 'TECHNICIAN' }], permissions: [{ code: 'maintenance.manage' }] });
    expect(await runRole()).toBe('/acceso-denegado' as never);
    expect(createUrlTree).toHaveBeenCalledWith(['/acceso-denegado']);
  });

  it('lets the right role through', async () => {
    setup(jasmine.createSpy(), { roles: [{ code: 'SUPERVISOR' }], permissions: [{ code: 'maintenance.manage' }] });
    expect(await runRole()).toBeTrue();
  });
});
