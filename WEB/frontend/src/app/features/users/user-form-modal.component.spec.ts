import { ComponentFixture, TestBed } from '@angular/core/testing';
import { of } from 'rxjs';

import { ManagedAccount } from '../../core/users.service';
import { UsersStore } from '../../core/users.store';
import { UserFormModalComponent } from './user-form-modal.component';

const account = (over: Partial<ManagedAccount> = {}): ManagedAccount => ({
  id: 5, email: 'ana@x.com', full_name: 'Ana Pérez', phone: null, employee_code: null, is_active: true,
  roles: [{ id: 2, code: 'EMPLOYEE', name: 'Empleado' }], created_at: '2026-01-01T00:00:00Z',
  last_login_at: null, linked: false, ...over,
});

describe('UserFormModalComponent', () => {
  let fixture: ComponentFixture<UserFormModalComponent>;
  let store: jasmine.SpyObj<UsersStore>;
  const root = () => fixture.nativeElement as HTMLElement;
  const input = (id: string) => root().querySelector('#' + id) as HTMLInputElement;

  function create(user: ManagedAccount | null): void {
    store = jasmine.createSpyObj('UsersStore', ['create', 'update', 'replaceRoles']);
    store.create.and.returnValue(of({ ok: true, fieldErrors: {} }));
    store.update.and.returnValue(of({ ok: true, fieldErrors: {} }));
    TestBed.configureTestingModule({ providers: [{ provide: UsersStore, useValue: store }] });
    fixture = TestBed.createComponent(UserFormModalComponent);
    fixture.componentRef.setInput('roles', [{ id: 1, code: 'ADMIN', name: 'Administrador' }, { id: 2, code: 'EMPLOYEE', name: 'Empleado' }]);
    fixture.componentRef.setInput('user', user);
    document.body.appendChild(root());
    fixture.detectChanges();
  }

  afterEach(() => root().remove());

  it('lets the name be typed when creating', () => {
    create(null);

    expect(input('uf-name').disabled).toBeFalse();
  });

  it('locks the name when editing: each person changes it from their own profile', () => {
    create(account());

    expect(input('uf-name').disabled).toBeTrue();
    expect(input('uf-name').value).toBe('Ana Pérez');
    expect(root().textContent).toContain('Cada persona edita su nombre desde su perfil');
  });

  it('never sends the name when editing', () => {
    create(account());
    input('uf-phone').value = '+57 300 123 4567';
    input('uf-phone').dispatchEvent(new Event('input'));

    (root().querySelector('form') as HTMLFormElement).dispatchEvent(new Event('submit'));

    expect(store.update).toHaveBeenCalledWith(5, { phone: '+57 300 123 4567', employee_code: null, email: 'ana@x.com' });
  });

  it('can edit someone who already signed in (locked e-mail) without errors', () => {
    create(account({ linked: true }));
    input('uf-phone').value = '+57 300 123 4567';
    input('uf-phone').dispatchEvent(new Event('input'));

    (root().querySelector('form') as HTMLFormElement).dispatchEvent(new Event('submit'));

    expect(input('uf-email').disabled).toBeTrue();
    expect(store.update).toHaveBeenCalledWith(5, { phone: '+57 300 123 4567', employee_code: null });
  });
});
