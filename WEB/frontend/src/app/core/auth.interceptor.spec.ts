import { HttpClient, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';

import { apiBaseUrl } from './api.config';
import { authInterceptor } from './auth.interceptor';
import { ClerkService } from './clerk.service';
import { ToastService } from './toast.service';

describe('authInterceptor', () => {
  let http: HttpClient;
  let backend: HttpTestingController;
  let clerk: { getToken: jasmine.Spy; refreshToken: jasmine.Spy; signOut: jasmine.Spy };
  let toasts: ToastService;
  const url = `${apiBaseUrl()}/tickets`;
  const settle = () => new Promise((resolve) => setTimeout(resolve));

  beforeEach(() => {
    clerk = {
      getToken: jasmine.createSpy('getToken').and.resolveTo('old-token'),
      refreshToken: jasmine.createSpy('refreshToken').and.resolveTo('new-token'),
      signOut: jasmine.createSpy('signOut').and.resolveTo(undefined),
    };
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(withInterceptors([authInterceptor])),
        provideHttpClientTesting(),
        { provide: ClerkService, useValue: clerk },
      ],
    });
    http = TestBed.inject(HttpClient);
    backend = TestBed.inject(HttpTestingController);
    toasts = TestBed.inject(ToastService);
  });

  afterEach(() => backend.verify());

  it('sends the token to the API and leaves other hosts alone', async () => {
    http.get(url).subscribe();
    await settle();
    expect(backend.expectOne(url).request.headers.get('Authorization')).toBe('Bearer old-token');

    http.get('https://fonts.example.com/x.css').subscribe();
    expect(backend.expectOne('https://fonts.example.com/x.css').request.headers.has('Authorization')).toBeFalse();
    expect(clerk.getToken).toHaveBeenCalledTimes(1);
  });

  it('on a 401 asks for a fresh token and retries once with it', async () => {
    let result: unknown;
    http.get(url).subscribe((value) => (result = value));
    await settle();
    backend.expectOne(url).flush({ detail: 'expired' }, { status: 401, statusText: 'Unauthorized' });
    await settle();

    const retry = backend.expectOne(url);
    expect(retry.request.headers.get('Authorization')).toBe('Bearer new-token');
    retry.flush({ ok: true });

    expect(result).toEqual({ ok: true });
    expect(clerk.refreshToken).toHaveBeenCalledTimes(1);
    expect(clerk.signOut).not.toHaveBeenCalled();
  });

  it('signs out when the retry is also refused', async () => {
    let failed = false;
    http.get(url).subscribe({ error: () => (failed = true) });
    await settle();
    backend.expectOne(url).flush({}, { status: 401, statusText: 'Unauthorized' });
    await settle();
    backend.expectOne(url).flush({}, { status: 401, statusText: 'Unauthorized' });
    await settle();

    expect(failed).toBeTrue();
    expect(clerk.signOut).toHaveBeenCalledTimes(1);
    expect(clerk.refreshToken).toHaveBeenCalledTimes(1); // never a second refresh: no loop
  });

  it('signs out when no new token can be had', async () => {
    clerk.refreshToken.and.resolveTo(null);
    let failed = false;
    http.get(url).subscribe({ error: () => (failed = true) });
    await settle();
    backend.expectOne(url).flush({}, { status: 401, statusText: 'Unauthorized' });
    await settle();

    expect(failed).toBeTrue();
    expect(clerk.signOut).toHaveBeenCalledTimes(1);
  });

  it('on a 403 says so in Spanish and passes the error on, without retrying', async () => {
    let status = 0;
    http.get(url).subscribe({ error: (error) => (status = error.status) });
    await settle();
    backend.expectOne(url).flush({ detail: 'x', code: 'forbidden' }, { status: 403, statusText: 'Forbidden' });
    await settle();

    expect(status).toBe(403);
    expect(toasts.toasts().map((t) => t.message)).toEqual(['No tienes permiso para realizar esta acción.']);
    expect(clerk.refreshToken).not.toHaveBeenCalled();
  });

  it('does not repeat the same notice when a screen also reports the 403', async () => {
    http.get(url).subscribe({ error: () => toasts.error('No tienes permiso para realizar esta acción.') });
    await settle();
    backend.expectOne(url).flush({}, { status: 403, statusText: 'Forbidden' });
    await settle();

    expect(toasts.toasts().length).toBe(1);
  });

  it('leaves other errors to the screens', async () => {
    http.get(url).subscribe({ error: () => undefined });
    await settle();
    backend.expectOne(url).flush({}, { status: 500, statusText: 'Server Error' });
    await settle();

    expect(toasts.toasts()).toEqual([]);
    expect(clerk.refreshToken).not.toHaveBeenCalled();
  });
});
