import { BehaviorSubject } from 'rxjs';

import { watchAuthSession } from './auth-session';
import { ClerkState } from './clerk.types';

const signedIn = (id: string): ClerkState => ({ isSignedIn: true, user: { id }, session: null });
const signedOut: ClerkState = { isSignedIn: false, user: null, session: null };

describe('watchAuthSession', () => {
  let state$: BehaviorSubject<ClerkState>;
  let router: { url: string; navigateByUrl: jasmine.Spy };
  let profile: { clear: jasmine.Spy };
  let notifications: { clear: jasmine.Spy };

  function start(initial: ClerkState, url: string): void {
    state$ = new BehaviorSubject<ClerkState>(initial);
    router = { url, navigateByUrl: jasmine.createSpy('navigateByUrl').and.resolveTo(true) };
    profile = { clear: jasmine.createSpy('profile.clear') };
    notifications = { clear: jasmine.createSpy('notifications.clear') };
    watchAuthSession({
      clerk: { state$ } as never,
      router: router as never,
      profile: profile as never,
      notifications: notifications as never,
    });
    profile.clear.calls.reset();
    notifications.clear.calls.reset();
  }

  it('clears cached user data and returns to login when the session ends', () => {
    start(signedIn('user_a'), '/dashboard');
    state$.next(signedOut);
    expect(profile.clear).toHaveBeenCalled();
    expect(notifications.clear).toHaveBeenCalled();
    expect(router.navigateByUrl).toHaveBeenCalledWith('/auth/login');
  });

  it('does not navigate when sign-out happens on the login page', () => {
    start(signedIn('user_a'), '/auth/login');
    state$.next(signedOut);
    expect(router.navigateByUrl).not.toHaveBeenCalled();
  });

  it('clears cached data when switching to a different account', () => {
    start(signedIn('user_a'), '/dashboard');
    state$.next(signedIn('user_b'));
    expect(profile.clear).toHaveBeenCalled();
    expect(router.navigateByUrl).not.toHaveBeenCalled();
  });

  it('ignores repeated emissions for the same user', () => {
    start(signedIn('user_a'), '/dashboard');
    state$.next(signedIn('user_a'));
    expect(profile.clear).not.toHaveBeenCalled();
  });

  it('goes to the dashboard when a session opens on the sign-up screen', () => {
    start(signedOut, '/auth/sign-up#/verify-email-address');
    state$.next(signedIn('user_a'));
    expect(router.navigateByUrl).toHaveBeenCalledWith('/dashboard');
  });

  it('does not redirect when a session opens away from the public auth screens', () => {
    start(signedOut, '/dashboard');
    state$.next(signedIn('user_a'));
    expect(router.navigateByUrl).not.toHaveBeenCalled();
  });
});
