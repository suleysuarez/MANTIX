import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { BehaviorSubject } from 'rxjs';

import { PendingUsersState, PendingUsersStore } from '../../core/pending-users.store';
import { PendingUsersComponent } from './pending-users.component';

const state = (over: Partial<PendingUsersState> = {}): PendingUsersState => ({
  users: [{ id: 1, email: 'ana@x.com', full_name: 'Ana Pérez' }, { id: 2, email: 'luis@x.com', full_name: 'Luis Gómez' }],
  roles: [{ id: 1, code: 'ADMIN', name: 'Administrador' }, { id: 2, code: 'EMPLOYEE', name: 'Empleado' }],
  loading: false, savingUserId: null, error: '', ...over,
});

describe('PendingUsersComponent', () => {
  let fixture: ComponentFixture<PendingUsersComponent>;
  let store: jasmine.SpyObj<PendingUsersStore>;
  let subject: BehaviorSubject<PendingUsersState>;
  const root = () => fixture.nativeElement as HTMLElement;
  const text = () => root().textContent!.replace(/\s+/g, ' ');

  function create(initial: PendingUsersState = state()): void {
    subject = new BehaviorSubject(initial);
    store = Object.assign(jasmine.createSpyObj('PendingUsersStore', ['load', 'assignRoles']), { state$: subject.asObservable() }) as unknown as jasmine.SpyObj<PendingUsersStore>;
    TestBed.configureTestingModule({ providers: [provideRouter([]), { provide: PendingUsersStore, useValue: store }] });
    fixture = TestBed.createComponent(PendingUsersComponent);
    document.body.appendChild(root());
    fixture.detectChanges();
  }

  afterEach(() => root().remove());

  it('is in Spanish and counts the people waiting', () => {
    create();

    expect(store.load).toHaveBeenCalled();
    expect(text()).toContain('Usuarios pendientes');
    expect(text()).toContain('en espera');
    expect(text()).not.toContain('Pending authorization');
    expect(root().querySelectorAll('article').length).toBe(2);
    expect(text()).toContain('Ana Pérez');
    expect(text()).toContain('Administrador');
  });

  it('keeps the assign button off until a role is chosen, then sends the chosen roles', () => {
    create();
    const card = root().querySelector('article') as HTMLElement;
    const assign = card.querySelector('button') as HTMLButtonElement;
    expect(assign.disabled).toBeTrue();
    expect(card.textContent).toContain('Elige al menos un rol');

    const second = card.querySelectorAll('input[type="checkbox"]')[1] as HTMLInputElement;
    second.checked = true;
    second.dispatchEvent(new Event('change'));
    fixture.detectChanges();
    expect(assign.disabled).toBeFalse();
    expect(card.textContent).toContain('1 rol elegido');

    assign.click();
    expect(store.assignRoles).toHaveBeenCalledWith(1, [2]);
  });

  it('shows a friendly empty state', () => {
    create(state({ users: [] }));

    expect(text()).toContain('No hay nadie esperando autorización');
  });

  it('shows the error with a retry', () => {
    create(state({ users: [], error: 'No se pudieron cargar los usuarios pendientes.' }));

    expect(root().querySelector('[role="alert"]')?.textContent).toContain('No se pudieron cargar');
    (Array.from(root().querySelectorAll('button')).find((b) => b.textContent!.includes('Reintentar')) as HTMLButtonElement).click();
    expect(store.load).toHaveBeenCalledTimes(2);
  });

  it('disables the button of the person being saved', () => {
    create(state({ savingUserId: 1 }));

    const first = root().querySelector('article button') as HTMLButtonElement;
    expect(first.disabled).toBeTrue();
    expect(first.textContent).toContain('Asignando');
  });
});
