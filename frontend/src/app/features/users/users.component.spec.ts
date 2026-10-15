import { ComponentFixture, TestBed } from '@angular/core/testing';
import { BehaviorSubject, of } from 'rxjs';

import { ExportService } from '../../core/export.service';
import { LocalProfileService } from '../../core/local-profile.service';
import { ManagedAccount } from '../../core/users.service';
import { EMPTY_USER_FILTERS, UsersState, UsersStore } from '../../core/users.store';
import { UsersComponent } from './users.component';

const account = (id: number, name: string, over: Partial<ManagedAccount> = {}): ManagedAccount => ({
  id, email: `${id}@mantix.io`, full_name: name, phone: null, employee_code: `EMP-${id}`, is_active: true,
  roles: [{ id: 2, code: 'EMPLOYEE', name: 'Empleado' }], created_at: '2026-01-01T00:00:00Z',
  last_login_at: '2026-10-01T10:00:00Z', linked: true, ...over,
});

const state = (users: ManagedAccount[]): UsersState => ({
  filters: EMPTY_USER_FILTERS, rangeError: '', users, total: users.length, page: 1, loading: false, error: '',
  roles: [{ id: 1, code: 'ADMIN', name: 'Administrador' }, { id: 2, code: 'EMPLOYEE', name: 'Empleado' }],
  summary: {
    total: 3, active: 2, inactive: 1, never_signed_in: 1, without_role: 0,
    by_role: [{ code: 'ADMIN', name: 'Administrador', count: 1 }, { code: 'EMPLOYEE', name: 'Empleado', count: 2 }],
    recent_access: [{ id: 1, full_name: 'Ana Pérez', email: 'a@x.com', last_login_at: '2026-10-14T10:00:00Z' }],
  },
  summaryLoading: false, busy: false,
});

describe('UsersComponent', () => {
  let fixture: ComponentFixture<UsersComponent>;
  let store: jasmine.SpyObj<UsersStore>;
  const root = () => fixture.nativeElement as HTMLElement;
  const text = () => root().textContent!.replace(/\s+/g, ' ');
  const button = (label: string) =>
    Array.from(root().querySelectorAll('button')).find((b) => (b.textContent + (b.getAttribute('aria-label') ?? '')).includes(label)) as HTMLButtonElement;

  async function create(users: ManagedAccount[], selfId = 99): Promise<void> {
    store = Object.assign(jasmine.createSpyObj('UsersStore', ['load', 'setFilters', 'clearFilters', 'setPage', 'setActive', 'create', 'update', 'replaceRoles', 'resetPassword']), {
      state$: new BehaviorSubject(state(users)),
    }) as unknown as jasmine.SpyObj<UsersStore>;
    store.setActive.and.returnValue(of({ ok: true, fieldErrors: {} }));
    TestBed.configureTestingModule({
      providers: [
        { provide: UsersStore, useValue: store },
        { provide: LocalProfileService, useValue: { getProfile: () => Promise.resolve({ id: selfId }) } },
        { provide: ExportService, useValue: { options: () => of({ report: 'users', title: 'Usuarios', columns: [], formats: ['pdf', 'xlsx'], max_rows: 10000, warn_rows: 2000, max_range_days: 366 }), count: () => of({ total: 3, max_rows: 10000, warn_rows: 2000, over_limit: false, large: false }), export: () => of() } },
      ],
    });
    fixture = TestBed.createComponent(UsersComponent);
    document.body.appendChild(root());
    fixture.detectChanges();
    await fixture.whenStable();
    fixture.detectChanges();
  }

  afterEach(() => root().remove());

  it('loads the data and shows the indicators of its own', async () => {
    await create([account(1, 'Ana Pérez')]);

    expect(store.load).toHaveBeenCalled();
    expect(text()).toContain('Usuarios activos por rol');
    expect(text()).toContain('Últimos accesos');
    expect(text()).toContain('Sin primer ingreso');
    expect(text()).toContain('Administrador');
  });

  it('lists each person with their roles and state', async () => {
    await create([account(1, 'Ana Pérez'), account(2, 'Luis Gómez', { is_active: false }), account(3, 'Eva Ríos', { last_login_at: null, linked: false })]);

    const rows = Array.from(root().querySelectorAll('tbody tr')).map((r) => r.textContent!.replace(/\s+/g, ' '));
    expect(rows.length).toBe(3);
    expect(rows[0]).toContain('Ana Pérez');
    expect(rows[0]).toContain('Empleado');
    expect(rows[0]).toContain('Activo');
    expect(rows[1]).toContain('Inactivo');
    expect(rows[2]).toContain('Pendiente de primer ingreso');
    expect(rows[2]).toContain('Nunca');
  });

  it('shows an empty state when nothing matches', async () => {
    await create([]);

    expect(text()).toContain('Aún no hay usuarios');
  });

  it('opens the creation form from the header button', async () => {
    await create([account(1, 'Ana Pérez')]);

    button('Nuevo usuario').click();
    fixture.detectChanges();

    expect(root().querySelector('[role="dialog"]')?.textContent).toContain('Nuevo usuario');
  });

  it('cannot deactivate the signed-in user or reset their own password', async () => {
    await create([account(99, 'Yo Mismo'), account(2, 'Otra Persona')]);

    expect(button('Desactivar a Yo Mismo').disabled).toBeTrue();
    expect(button('Restablecer la contraseña de Yo Mismo').disabled).toBeTrue();
    expect(button('Desactivar a Otra Persona').disabled).toBeFalse();
  });

  it('cannot reset the password of someone who has not signed in yet', async () => {
    await create([account(2, 'Pendiente', { linked: false, last_login_at: null })]);

    expect(button('Restablecer la contraseña de Pendiente').disabled).toBeTrue();
  });

  it('asks for confirmation before deactivating, and reactivates in one click', async () => {
    await create([account(2, 'Otra Persona'), account(3, 'Dada de baja', { is_active: false })]);

    button('Desactivar a Otra Persona').click();
    fixture.detectChanges();
    expect(root().querySelector('[role="alertdialog"]')?.textContent).toContain('¿Desactivar a Otra Persona?');
    expect(store.setActive).not.toHaveBeenCalled();

    const confirm = Array.from(root().querySelectorAll('[role="alertdialog"] button')).find((b) => b.textContent?.trim() === 'Desactivar') as HTMLButtonElement;
    confirm.click();
    expect(store.setActive).toHaveBeenCalledWith(jasmine.objectContaining({ id: 2 }), false);

    button('Activar a Dada de baja').click();
    expect(store.setActive).toHaveBeenCalledWith(jasmine.objectContaining({ id: 3 }), true);
  });

  it('sorts by the clicked column and flips the direction', async () => {
    await create([account(1, 'Ana Pérez')]);

    button('Creado').click();
    expect(store.setFilters).toHaveBeenCalledWith({ sort: 'created_at' });
  });
});
