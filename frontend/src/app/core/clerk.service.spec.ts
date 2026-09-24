import { TestBed } from '@angular/core/testing';
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
      session: { getToken: jasmine.createSpy('getToken').and.resolveTo('clerk-token') },
      load: jasmine.createSpy('load').and.resolveTo(),
      addListener: jasmine.createSpy('addListener').and.callFake((listener) => {
        stateListener = listener;
        return () => undefined;
      }),
      signOut,
      mountSignIn: jasmine.createSpy('mountSignIn'),
      unmountSignIn: jasmine.createSpy('unmountSignIn'),
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

  it('delegates logout to Clerk', async () => {
    await service.signOut();
    expect(signOut).toHaveBeenCalled();
  });
});
