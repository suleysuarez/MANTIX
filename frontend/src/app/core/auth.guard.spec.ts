import { HttpRequest, HttpResponse } from '@angular/common/http';
import { TestBed } from '@angular/core/testing';
import { Router } from '@angular/router';
import { of } from 'rxjs';

import { authGuard, authorizedGuard, permissionGuard } from './auth.guard';
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
