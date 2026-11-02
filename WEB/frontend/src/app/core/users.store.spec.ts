import { HttpErrorResponse } from '@angular/common/http';
import { TestBed } from '@angular/core/testing';
import { of, throwError } from 'rxjs';

import { AdminUsersService } from './admin-users.service';
import { ToastService } from './toast.service';
import { ManagedAccount, UsersService, UsersSummary } from './users.service';
import { UsersState, UsersStore } from './users.store';

const account = (id: number, over: Partial<ManagedAccount> = {}): ManagedAccount => ({
  id, email: `u${id}@x.com`, full_name: `Usuario ${id}`, phone: null, employee_code: null, is_active: true, roles: [],
  created_at: '2026-01-01T00:00:00Z', last_login_at: null, linked: false, ...over,
});

const summary: UsersSummary = { total: 2, active: 2, inactive: 0, never_signed_in: 1, without_role: 0, by_role: [], recent_access: [] };

describe('UsersStore', () => {
  let api: jasmine.SpyObj<UsersService>;
  let roles: jasmine.SpyObj<AdminUsersService>;
  let toasts: jasmine.SpyObj<ToastService>;
  let store: UsersStore;
  let latest: UsersState;

  beforeEach(() => {
    api = jasmine.createSpyObj('UsersService', ['listPage', 'summary', 'create', 'update', 'setActive', 'replaceRoles', 'resetPassword']);
    roles = jasmine.createSpyObj('AdminUsersService', ['listRoles']);
    toasts = jasmine.createSpyObj('ToastService', ['success', 'error']);
    api.listPage.and.returnValue(of({ items: [account(1), account(2)], total: 2 }));
    api.summary.and.returnValue(of(summary));
    roles.listRoles.and.returnValue(of([{ id: 1, code: 'ADMIN', name: 'Administrador' }]));
    TestBed.configureTestingModule({
      providers: [
        UsersStore,
        { provide: UsersService, useValue: api },
        { provide: AdminUsersService, useValue: roles },
        { provide: ToastService, useValue: toasts },
      ],
    });
    store = TestBed.inject(UsersStore);
    store.state$.subscribe((state) => (latest = state));
  });

  it('loads the first page, the indicators and the roles', () => {
    store.load();

    expect(latest.users.length).toBe(2);
    expect(latest.total).toBe(2);
    expect(latest.summary?.never_signed_in).toBe(1);
    expect(latest.roles.length).toBe(1);
    expect(latest.loading).toBeFalse();
  });

  it('reports a failure to load the list', () => {
    api.listPage.and.returnValue(throwError(() => new Error('boom')));

    store.load();

    expect(latest.loading).toBeFalse();
    expect(latest.error).toBe('No se pudieron cargar los usuarios.');
  });

  it('filters on the server and goes back to page 1', () => {
    store.load();
    api.listPage.calls.reset();

    store.setFilters({ role: 'ADMIN', status: 'inactive', search: ' ana ' });

    const query = api.listPage.calls.mostRecent().args[0]!;
    expect(query.role).toBe('ADMIN');
    expect(query.status).toBe('inactive');
    expect(query.search).toBe('ana');
    expect(query.page).toBe(1);
  });

  it('does not query while the creation date range is invalid', () => {
    store.load();
    api.listPage.calls.reset();

    store.setFilters({ createdFrom: '2026-05-10', createdTo: '2026-05-01' });

    expect(latest.rangeError).not.toBe('');
    expect(api.listPage).not.toHaveBeenCalled();
  });

  it('clears the filters but keeps the sort order', () => {
    store.load();
    store.setFilters({ sort: '-created_at', role: 'ADMIN' });

    store.clearFilters();

    expect(latest.filters.role).toBe('');
    expect(latest.filters.sort).toBe('-created_at');
  });

  it('steps back a page when the last one is left empty', () => {
    store.load();
    api.listPage.calls.reset();
    api.listPage.and.callFake((query) => of(query?.page === 2 ? { items: [], total: 10 } : { items: [account(1)], total: 10 }));

    store.setPage(2);

    expect(api.listPage.calls.allArgs().map(([query]) => query?.page)).toEqual([2, 1]);
    expect(latest.page).toBe(1);
  });

  it('refreshes list and indicators after creating, and says so', () => {
    store.load();
    api.create.and.returnValue(of(account(3)));
    api.listPage.calls.reset();
    api.summary.calls.reset();
    let ok = false;

    store.create({ email: 'n@x.com', full_name: 'Nuevo Usuario', phone: null, employee_code: null, role_ids: [1] }).subscribe((r) => (ok = r.ok));

    expect(ok).toBeTrue();
    expect(toasts.success).toHaveBeenCalled();
    expect(api.listPage).toHaveBeenCalled();
    expect(api.summary).toHaveBeenCalled();
    expect(latest.busy).toBeFalse();
  });

  it('returns the field errors of a 422 in Spanish, without refreshing', () => {
    store.load();
    const error = new HttpErrorResponse({
      status: 422,
      error: { code: 'validation_error', detail: 'x', errors: [{ field: 'email', message: 'bad', type: 'string_pattern_mismatch' }] },
    });
    api.create.and.returnValue(throwError(() => error));
    api.listPage.calls.reset();
    let result: { ok: boolean; fieldErrors: Record<string, string> } | undefined;

    store.create({ email: 'x', full_name: 'Nuevo Usuario', phone: null, employee_code: null, role_ids: [1] }).subscribe((r) => (result = r));

    expect(result?.ok).toBeFalse();
    expect(result?.fieldErrors['email']).toBe('El formato no es válido.');
    expect(toasts.error).toHaveBeenCalled();
    expect(api.listPage).not.toHaveBeenCalled();
    expect(latest.busy).toBeFalse();
  });

  it('names the person when activating and deactivating', () => {
    store.load();
    api.setActive.and.returnValue(of(account(1)));

    store.setActive(account(1), false).subscribe();
    store.setActive(account(1), true).subscribe();

    expect(toasts.success.calls.allArgs().map(([text]) => text)).toEqual(['Usuario 1 fue desactivado.', 'Usuario 1 fue activado.']);
  });

  it('sends the new password to the server and never keeps it in the state', () => {
    store.load();
    api.resetPassword.and.returnValue(of(undefined));

    store.resetPassword(2, 'Segura12345').subscribe();

    expect(api.resetPassword).toHaveBeenCalledWith(2, 'Segura12345');
    expect(JSON.stringify(latest)).not.toContain('Segura12345');
  });
});
