import { Directive, ElementRef, effect, inject, input } from '@angular/core';

import { requiresText } from '../core/permission-labels';
import { PermissionsService } from '../core/permissions.service';

/**
 * Deshabilita un botón o enlace si falta el permiso y explica por qué al pasar el cursor:
 *
 *     <button [requiresPermission]="'tickets:asignar'" (click)="asignar()">Asignar</button>
 *
 * Úsala donde conviene que la persona vea que la acción existe (y qué le falta); donde no, usa
 * `*hasPermission` para ocultarla. Con permiso no toca el elemento.
 */
// El nombre sin prefijo es el que se pidió (`*hasPermission`): se exceptúa la regla del prefijo `app`.
// eslint-disable-next-line @angular-eslint/directive-selector
@Directive({ selector: '[requiresPermission]', standalone: true })
export class RequiresPermissionDirective {
  private readonly permissions = inject(PermissionsService);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private original: { title: string | null; disabled: boolean } | null = null;

  readonly requiresPermission = input.required<string | readonly string[]>();

  constructor() {
    effect(() => {
      const wanted = this.requiresPermission();
      const codes = typeof wanted === 'string' ? [wanted] : wanted;
      this.permissions.codes();
      this.apply(this.permissions.hasAny(codes), codes);
    });
  }

  private apply(allowed: boolean, codes: readonly string[]): void {
    const element = this.host.nativeElement as HTMLElement & { disabled?: boolean };
    const isControl = 'disabled' in element;
    if (!allowed) {
      this.original ??= { title: element.getAttribute('title'), disabled: element.disabled === true };
      element.setAttribute('aria-disabled', 'true');
      element.setAttribute('title', requiresText(codes));
      if (isControl) {
        element.disabled = true;
      } else {
        element.setAttribute('tabindex', '-1');
        element.style.pointerEvents = 'none';
      }
      element.classList.add('opacity-50', 'cursor-not-allowed');
    } else if (this.original) {
      element.removeAttribute('aria-disabled');
      if (this.original.title === null) {
        element.removeAttribute('title');
      } else {
        element.setAttribute('title', this.original.title);
      }
      if (isControl) {
        element.disabled = this.original.disabled;
      }
      element.classList.remove('opacity-50', 'cursor-not-allowed');
      this.original = null;
    }
  }
}
