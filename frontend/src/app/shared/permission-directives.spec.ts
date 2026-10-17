import { Component, signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { BehaviorSubject, Subject } from 'rxjs';

import { ClerkService } from '../core/clerk.service';
import { LocalProfileService } from '../core/local-profile.service';

import { permissionLabel, requiresText } from '../core/permission-labels';
import { PermissionsService } from '../core/permissions.service';
import { HasPermissionDirective } from './has-permission.directive';
import { RequiresPermissionDirective } from './requires-permission.directive';

/** Las dos piezas que el servicio necesita, sin red. */
const COLLABORATORS = [
  { provide: LocalProfileService, useValue: { changes: new Subject<void>(), getProfile: () => Promise.resolve({}), can: () => Promise.resolve(false), clearQuietly: () => undefined } },
  { provide: ClerkService, useValue: { state$: new BehaviorSubject({ isSignedIn: false, user: null, session: null }).asObservable() } },
];

/** El servicio real con los permisos fijados a mano (sin red). */
function grant(codes: string[]): PermissionsService {
  const service = TestBed.inject(PermissionsService);
  (service as unknown as { granted: { set(value: Set<string>): void } }).granted.set(new Set(codes));
  return service;
}

@Component({
  standalone: true,
  imports: [HasPermissionDirective],
  template: `
    <button id="one" *hasPermission="'tickets:crear'">Nuevo</button>
    <button id="any" *hasPermission="['usuarios:ver', 'tickets:ver']">Cualquiera</button>
    <button id="all" *hasPermission="['usuarios:ver', 'tickets:ver']; mode: 'all'">Todos</button>
    <button id="dyn" *hasPermission="wanted()">Dinámico</button>
    <ng-template #nothing><span id="otherwise">Sin acceso</span></ng-template>
    <button id="else" *hasPermission="'configuracion:editar'; else nothing">Config</button>
  `,
})
class HasHostComponent {
  readonly wanted = signal('perfil:ver');
}

@Component({
  standalone: true,
  imports: [RequiresPermissionDirective],
  template: `
    <button id="assign" type="button" title="Asignar un técnico" [requiresPermission]="'tickets:asignar'">Asignar</button>
    <button id="either" type="button" [requiresPermission]="['tickets:asignar', 'tickets:editar']">Cualquiera</button>
    <a id="link" href="#" [requiresPermission]="'reportes:exportar'">Exportar</a>
  `,
})
class RequiresHostComponent {}

describe('hasPermission (structural)', () => {
  function render(codes: string[]) {
    TestBed.configureTestingModule({ providers: COLLABORATORS });
    grant(codes);
    const fixture = TestBed.createComponent(HasHostComponent);
    fixture.detectChanges();
    return fixture;
  }
  const ids = (root: HTMLElement) => Array.from(root.querySelectorAll('[id]')).map((el) => el.id);

  it('shows only what the person may use', () => {
    const fixture = render(['tickets:crear', 'tickets:ver', 'perfil:ver']);
    expect(ids(fixture.nativeElement)).toEqual(['one', 'any', 'dyn', 'otherwise']);
  });

  it('with a list, any of them is enough unless mode is all', () => {
    expect(ids(render(['usuarios:ver']).nativeElement)).toContain('any');
    TestBed.resetTestingModule();
    const both = render(['usuarios:ver', 'tickets:ver']);
    expect(ids(both.nativeElement)).toContain('all');
  });

  it('shows the else template when the permission is missing', () => {
    const fixture = render([]);
    expect(fixture.nativeElement.querySelector('#otherwise').textContent).toBe('Sin acceso');
    expect(fixture.nativeElement.querySelector('#else')).toBeNull();
  });

  it('follows the permissions when they change and when the wanted code changes', () => {
    const fixture = render([]);
    expect(ids(fixture.nativeElement)).not.toContain('one');

    grant(['tickets:crear']);
    fixture.detectChanges();
    expect(ids(fixture.nativeElement)).toContain('one');

    fixture.componentInstance.wanted.set('usuarios:ver');
    fixture.detectChanges();
    expect(ids(fixture.nativeElement)).not.toContain('dyn');
    grant(['usuarios:ver']);
    fixture.detectChanges();
    expect(ids(fixture.nativeElement)).toContain('dyn');
  });
});

describe('requiresPermission (disable with an explanation)', () => {
  function render(codes: string[]) {
    TestBed.configureTestingModule({ providers: COLLABORATORS });
    grant(codes);
    const fixture = TestBed.createComponent(RequiresHostComponent);
    fixture.detectChanges();
    return fixture;
  }
  const el = (fixture: { nativeElement: HTMLElement }, id: string) => fixture.nativeElement.querySelector('#' + id) as HTMLButtonElement;

  it('disables the control and says what permission it needs', () => {
    const fixture = render([]);
    expect(el(fixture, 'assign').disabled).toBeTrue();
    expect(el(fixture, 'assign').getAttribute('aria-disabled')).toBe('true');
    expect(el(fixture, 'assign').title).toBe('Requiere permiso de Tickets · asignar');
    expect(el(fixture, 'either').title).toBe('Requiere permiso de Tickets · asignar o Tickets · editar');
  });

  it('leaves the control alone when the person has the permission', () => {
    const fixture = render(['tickets:asignar']);
    expect(el(fixture, 'assign').disabled).toBeFalse();
    expect(el(fixture, 'assign').title).toBe('Asignar un técnico');
    expect(el(fixture, 'assign').hasAttribute('aria-disabled')).toBeFalse();
  });

  it('any one of a list is enough', () => {
    const fixture = render(['tickets:editar']);
    expect(el(fixture, 'either').disabled).toBeFalse();
  });

  it('blocks a link too, and gives the original back when the permission arrives', () => {
    const fixture = render([]);
    expect(el(fixture, 'link').getAttribute('tabindex')).toBe('-1');
    expect(el(fixture, 'link').style.pointerEvents).toBe('none');

    grant(['reportes:exportar', 'tickets:asignar']);
    fixture.detectChanges();

    expect(el(fixture, 'link').getAttribute('aria-disabled')).toBeNull();
    expect(el(fixture, 'assign').disabled).toBeFalse();
    expect(el(fixture, 'assign').title).toBe('Asignar un técnico');
  });
});

describe('permission labels', () => {
  it('reads a code in Spanish', () => {
    expect(permissionLabel('tickets:asignar')).toBe('Tickets · asignar');
    expect(permissionLabel('configuracion:editar')).toBe('Configuración · editar');
    expect(permissionLabel('tickets:cambiar_estado')).toBe('Tickets · cambiar el estado');
  });

  it('shows an unknown code as it is, without inventing a name', () => {
    expect(permissionLabel('algo:raro')).toBe('algo:raro');
  });

  it('builds the tooltip', () => {
    expect(requiresText('usuarios:crear')).toBe('Requiere permiso de Usuarios · crear');
    expect(requiresText(['equipos:editar', 'equipos:importar'])).toBe('Requiere permiso de Equipos · editar o Equipos · importar');
  });
});
