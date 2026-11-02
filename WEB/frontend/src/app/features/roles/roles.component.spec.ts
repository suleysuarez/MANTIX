import { HttpErrorResponse } from '@angular/common/http';
import { TestBed } from '@angular/core/testing';
import { of, throwError } from 'rxjs';

import { PermissionsService } from '../../core/permissions.service';
import { RoleAdmin, RolesAdminService } from '../../core/roles-admin.service';
import { ToastService } from '../../core/toast.service';
import { PERMISSIONS, ROLES } from './roles-fixtures';
import { RolesComponent } from './roles.component';

describe('RolesComponent (matrix of permissions by role)', () => {
  let api: jasmine.SpyObj<RolesAdminService>;
  let toast: ToastService;

  async function render(actorRoles: string[] = ['ADMIN'], roles: RoleAdmin[] = ROLES) {
    api = jasmine.createSpyObj<RolesAdminService>('RolesAdminService', ['list', 'permissions', 'create', 'update', 'setPermissions', 'remove']);
    api.list.and.returnValue(of(roles));
    api.permissions.and.returnValue(of(PERMISSIONS));
    TestBed.configureTestingModule({
      providers: [
        { provide: RolesAdminService, useValue: api },
        { provide: PermissionsService, useValue: { roles: () => actorRoles } },
      ],
    });
    toast = TestBed.inject(ToastService);
    spyOn(toast, 'success');
    spyOn(toast, 'error');
    const fixture = TestBed.createComponent(RolesComponent);
    document.body.appendChild(fixture.nativeElement);
    fixture.detectChanges();
    await fixture.whenStable();
    fixture.detectChanges();
    return fixture;
  }
  const root = (fixture: { nativeElement: HTMLElement }) => fixture.nativeElement;
  const box = (fixture: { nativeElement: HTMLElement }, label: string) =>
    root(fixture).querySelector(`input[aria-label="${label}"]`) as HTMLInputElement;
  const text = (fixture: { nativeElement: HTMLElement }) => root(fixture).textContent!.replace(/\s+/g, ' ');

  afterEach(() => document.querySelectorAll('app-roles').forEach((el) => el.remove()));

  it('draws one column per role and one row per permission, grouped by resource', async () => {
    const fixture = await render();
    const headers = Array.from(root(fixture).querySelectorAll('thead th')).map((th) => th.textContent!.trim());
    expect(headers.length).toBe(1 + ROLES.length);
    expect(text(fixture)).toContain('Solicitante');
    expect(text(fixture)).toContain('Compras');
    expect(root(fixture).querySelectorAll('tbody th[scope="colgroup"]').length).toBe(2);
    expect(root(fixture).querySelectorAll('tbody th[scope="row"]').length).toBe(PERMISSIONS.length);
  });

  it('marks base and custom roles and shows who each one inherits from', async () => {
    const fixture = await render();
    expect(text(fixture)).toContain('Base');
    expect(text(fixture)).toContain('Personalizado');
    expect(text(fixture)).toContain('hereda de Solicitante');
  });

  it('shows inherited permissions blocked, naming the role they come from', async () => {
    const fixture = await render();
    const inherited = box(fixture, 'Tickets · ver para Supervisor: heredado de Solicitante');
    expect(inherited).not.toBeNull();
    expect(inherited.disabled).toBeTrue();
    expect(inherited.checked).toBeTrue();
  });

  it('the Administrator column cannot be edited, and the role the person holds is locked too', async () => {
    const fixture = await render(['SUPERVISOR']);
    expect(box(fixture, 'Usuarios · asignar para Administrador').disabled).toBeTrue();
    expect(box(fixture, 'Tickets · ver todo para Supervisor').disabled).toBeTrue();
    expect(box(fixture, 'Tickets · asignar para Compras').disabled).toBeFalse();
  });

  it('ticking a permission is a pending change, applied to the roles below it, and only saved on request', async () => {
    const fixture = await render();
    expect(root(fixture).querySelector('[aria-label="Cambios sin guardar"]')).toBeNull();

    box(fixture, 'Tickets · ver para Compras').click();
    fixture.detectChanges();

    expect(box(fixture, 'Tickets · ver para Compras').checked).toBeTrue();
    expect(text(fixture)).toContain('1 cambio sin guardar en 1 rol.');
    expect(api.setPermissions).not.toHaveBeenCalled();
  });

  it('removing a permission from a role is reflected in the roles that inherit it', async () => {
    const fixture = await render();
    box(fixture, 'Tickets · ver para Solicitante').click();
    fixture.detectChanges();
    expect(box(fixture, 'Tickets · ver para Supervisor')?.checked).toBeFalsy();
  });

  it('saves every changed role, reports it and reloads', async () => {
    const fixture = await render();
    api.setPermissions.and.callFake((id) => of({ ...ROLES.find((r) => r.id === id)!, own_permissions: ['tickets:ver'] }));
    box(fixture, 'Tickets · ver para Compras').click();
    fixture.detectChanges();

    (Array.from(root(fixture).querySelectorAll('button')).find((b) => b.textContent!.includes('Guardar cambios')) as HTMLButtonElement).click();
    await fixture.whenStable();
    fixture.detectChanges();

    expect(api.setPermissions).toHaveBeenCalledOnceWith(5, ['tickets:ver']);
    expect(toast.success).toHaveBeenCalledWith('Permisos guardados.');
    expect(api.list).toHaveBeenCalledTimes(2);
    expect(root(fixture).querySelector('[aria-label="Cambios sin guardar"]')).toBeNull();
  });

  it('a refused save keeps the change pending and says why', async () => {
    const fixture = await render();
    api.setPermissions.and.returnValue(
      throwError(() => new HttpErrorResponse({ status: 403, error: { detail: 'No puedes conceder permisos que tú no tienes: usuarios:crear' } })),
    );
    box(fixture, 'Tickets · ver para Compras').click();
    fixture.detectChanges();

    (Array.from(root(fixture).querySelectorAll('button')).find((b) => b.textContent!.includes('Guardar cambios')) as HTMLButtonElement).click();
    await fixture.whenStable();
    fixture.detectChanges();

    expect(toast.error).toHaveBeenCalledWith(jasmine.stringContaining('No puedes conceder permisos'));
    expect(text(fixture)).toContain('1 cambio sin guardar');
  });

  it('discarding asks first and then restores what is saved', async () => {
    const fixture = await render();
    box(fixture, 'Tickets · ver para Compras').click();
    fixture.detectChanges();

    (Array.from(root(fixture).querySelectorAll('button')).find((b) => b.textContent!.trim() === 'Descartar') as HTMLButtonElement).click();
    fixture.detectChanges();
    expect(root(fixture).querySelector('[role="alertdialog"]')).not.toBeNull();

    (Array.from(root(fixture).querySelectorAll('[role="alertdialog"] button')).find((b) => b.textContent!.trim() === 'Descartar') as HTMLButtonElement).click();
    fixture.detectChanges();
    expect(box(fixture, 'Tickets · ver para Compras').checked).toBeFalse();
    expect(root(fixture).querySelector('[aria-label="Cambios sin guardar"]')).toBeNull();
  });

  it('a base role or one with users cannot be deleted, and the reason is on the button', async () => {
    const roles = [...ROLES.slice(0, 4), { ...ROLES[4], user_count: 2 }];
    const fixture = await render(['ADMIN'], roles);
    const del = (name: string) => root(fixture).querySelector(`button[aria-label="Eliminar el rol ${name}"]`) as HTMLButtonElement;
    expect(del('Técnico').disabled).toBeTrue();
    expect(del('Técnico').title).toContain('base');
    expect(del('Compras').disabled).toBeTrue();
    expect(del('Compras').title).toContain('usuarios asignados');
  });

  it('deleting an unused custom role asks for confirmation, then deletes it', async () => {
    const fixture = await render();
    api.remove.and.returnValue(of(undefined));
    (root(fixture).querySelector('button[aria-label="Eliminar el rol Compras"]') as HTMLButtonElement).click();
    fixture.detectChanges();
    expect(text(fixture)).toContain('¿Eliminar el rol «Compras»?');
    expect(api.remove).not.toHaveBeenCalled();

    (Array.from(root(fixture).querySelectorAll('[role="alertdialog"] button')).find((b) => b.textContent!.trim() === 'Eliminar') as HTMLButtonElement).click();
    await fixture.whenStable();
    fixture.detectChanges();

    expect(api.remove).toHaveBeenCalledOnceWith(5);
    expect(toast.success).toHaveBeenCalledWith('Rol «Compras» eliminado.');
  });

  it('opens a preview of what a role would see', async () => {
    const fixture = await render();
    (root(fixture).querySelector('button[aria-label="Probar como Técnico"]') as HTMLButtonElement).click();
    fixture.detectChanges();
    const dialog = root(fixture).querySelector('[role="dialog"]')!;
    expect(dialog.textContent).toContain('Probar como «Técnico»');
    expect(dialog.textContent).toContain('Tickets');
    expect(dialog.textContent).toContain('Lo asignado');
  });

  it('creates a role from the form and reloads the matrix', async () => {
    const fixture = await render();
    api.create.and.returnValue(of({ ...ROLES[4], id: 9, name: 'Jefe de zona' }));
    (Array.from(root(fixture).querySelectorAll('button')).find((b) => b.textContent!.includes('Nuevo rol')) as HTMLButtonElement).click();
    fixture.detectChanges();
    await fixture.whenStable();

    const name = root(fixture).querySelector('#rf-name') as HTMLInputElement;
    name.value = 'Jefe de zona';
    name.dispatchEvent(new Event('input'));
    fixture.detectChanges();
    (root(fixture).querySelector('form[role="dialog"]') as HTMLFormElement).dispatchEvent(new Event('submit'));
    await fixture.whenStable();
    fixture.detectChanges();

    expect(api.create).toHaveBeenCalledOnceWith({ name: 'Jefe de zona', description: null, parent_role_id: null, permissions: [] });
    expect(api.list).toHaveBeenCalledTimes(2);
  });

  it('shows the server explanation when a name is repeated and keeps the form open', async () => {
    const fixture = await render();
    api.create.and.returnValue(throwError(() => new HttpErrorResponse({ status: 409, error: { detail: 'Ya existe un rol llamado «Jefe».' } })));
    (Array.from(root(fixture).querySelectorAll('button')).find((b) => b.textContent!.includes('Nuevo rol')) as HTMLButtonElement).click();
    fixture.detectChanges();
    await fixture.whenStable();
    const name = root(fixture).querySelector('#rf-name') as HTMLInputElement;
    name.value = 'Jefe';
    name.dispatchEvent(new Event('input'));
    (root(fixture).querySelector('form[role="dialog"]') as HTMLFormElement).dispatchEvent(new Event('submit'));
    await fixture.whenStable();
    fixture.detectChanges();

    expect(root(fixture).querySelector('#rf-name-err')!.textContent).toContain('Ya existe un rol llamado «Jefe»');
    expect(root(fixture).querySelector('form[role="dialog"]')).not.toBeNull();
  });

  it('offers a retry when the roles cannot be loaded', async () => {
    api = jasmine.createSpyObj<RolesAdminService>('RolesAdminService', ['list', 'permissions']);
    api.list.and.returnValue(throwError(() => new HttpErrorResponse({ status: 0 })));
    api.permissions.and.returnValue(of(PERMISSIONS));
    TestBed.configureTestingModule({
      providers: [
        { provide: RolesAdminService, useValue: api },
        { provide: PermissionsService, useValue: { roles: () => ['ADMIN'] } },
      ],
    });
    const fixture = TestBed.createComponent(RolesComponent);
    fixture.detectChanges();
    await fixture.whenStable();
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('[role="alert"] button')).not.toBeNull();
  });
});
