import { HttpRequest, HttpResponse } from '@angular/common/http';
import { TestBed } from '@angular/core/testing';
import { Router } from '@angular/router';
import { of } from 'rxjs';

import { authGuard } from './auth.guard';
import { authInterceptor } from './auth.interceptor';
import { ClerkService } from './clerk.service';

function runGuard(): Promise<unknown> {
  return TestBed.runInInjectionContext(() =>
    authGuard({} as never, {} as never),
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
