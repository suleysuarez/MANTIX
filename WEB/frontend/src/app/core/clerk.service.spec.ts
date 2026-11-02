import { TestBed } from '@angular/core/testing';
import { Router } from '@angular/router';
import { ClerkService } from './clerk.service';
import { ClerkInstance, ClerkState } from './clerk.types';

describe('ClerkService', () => {
  let service: ClerkService;
  let stateListener: ((state: ClerkState) => void) | undefined;
  let signOut: jasmine.Spy;

  beforeEach(() => {
    signOut = jasmine.createSpy('signOut').and.resolveTo();
    const fakeClerk: ClerkInstance = {
      isSignedIn: true,
      user: { id: 'user_123' },
      session: { id: 'sess_1', getToken: jasmine.createSpy('getToken').and.resolveTo('clerk-token') },
      load: jasmine.createSpy('load').and.resolveTo(),
      addListener: jasmine.createSpy('addListener').and.callFake((listener) => {
        stateListener = listener;
        return () => undefined;
      }),
      signOut,
      mountSignIn: jasmine.createSpy('mountSignIn'),
      unmountSignIn: jasmine.createSpy('unmountSignIn'),
      mountSignUp: jasmine.createSpy('mountSignUp'),
      unmountSignUp: jasmine.createSpy('unmountSignUp'),
      mountUserButton: jasmine.createSpy('mountUserButton'),
      unmountUserButton: jasmine.createSpy('unmountUserButton'),
    };
    window.Clerk = fakeClerk;
    TestBed.configureTestingModule({ providers: [ClerkService] });
    service = TestBed.inject(ClerkService);
  });

  afterEach(() => {
    delete window.Clerk;
  });

  it('initializes Clerk and exposes the session token', async () => {
    await service.initialize();
    expect(service.isSignedIn).toBeTrue();
    expect(await service.getToken()).toBe('clerk-token');
    expect(stateListener).toBeDefined();
  });

  describe('Clerk navigation', () => {
    let routerPush: (to: string) => unknown;
    let navigateByUrl: jasmine.Spy;

    beforeEach(async () => {
      navigateByUrl = jasmine.createSpy('navigateByUrl').and.resolveTo(true);
      TestBed.resetTestingModule();
      TestBed.configureTestingModule({
        providers: [ClerkService, { provide: Router, useValue: { navigateByUrl } }],
      });
      const load = window.Clerk!.load as jasmine.Spy;
      await TestBed.inject(ClerkService).initialize();
      routerPush = load.calls.mostRecent().args[0].routerPush;
    });

    it('routes page changes through the Angular router', () => {
      routerPush('/dashboard');
      expect(navigateByUrl).toHaveBeenCalledWith('/dashboard', { replaceUrl: false });
    });

    it('keeps hash-only steps native so Clerk receives hashchange', () => {
      const path = window.location.pathname;
      routerPush(`${path}#/verify`);
      expect(window.location.hash).toBe('#/verify');
      expect(navigateByUrl).not.toHaveBeenCalled();
      history.replaceState(null, '', path);
    });
  });

  it('delegates logout to Clerk', async () => {
    await service.signOut();
    expect(signOut).toHaveBeenCalled();
  });
});
