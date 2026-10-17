import { Directive, EmbeddedViewRef, TemplateRef, ViewContainerRef, effect, inject, input } from '@angular/core';

import { PermissionsService } from '../core/permissions.service';

/**
 * Directiva estructural: muestra el elemento solo si la persona tiene el permiso.
 *
 *     <button *hasPermission="'tickets:crear'">Nuevo</button>
 *     <a *hasPermission="['reportes:ver', 'auditoria:ver']; mode: 'any'; else sinAcceso">…</a>
 *
 * Con una lista basta uno (`any`, por defecto) o hacen falta todos (`all`). Se actualiza sola si cambian
 * los permisos. Es comodidad de pantalla: el servidor vuelve a comprobar cada acción.
 */
// El nombre sin prefijo es el que se pidió (`*hasPermission`): se exceptúa la regla del prefijo `app`.
// eslint-disable-next-line @angular-eslint/directive-selector
@Directive({ selector: '[hasPermission]', standalone: true })
export class HasPermissionDirective {
  private readonly permissions = inject(PermissionsService);
  private readonly container = inject(ViewContainerRef);
  private readonly template = inject<TemplateRef<unknown>>(TemplateRef);
  private shown: EmbeddedViewRef<unknown> | null = null;
  private fallback: EmbeddedViewRef<unknown> | null = null;

  readonly hasPermission = input.required<string | readonly string[]>();
  readonly hasPermissionMode = input<'any' | 'all'>('any');
  readonly hasPermissionElse = input<TemplateRef<unknown> | null>(null);

  constructor() {
    effect(() => {
      const wanted = this.hasPermission();
      const codes = typeof wanted === 'string' ? [wanted] : wanted;
      // Leer las señales aquí hace que la vista se reevalúe cuando cambian.
      this.permissions.codes();
      const allowed = this.hasPermissionMode() === 'all' ? this.permissions.hasAll(codes) : this.permissions.hasAny(codes);
      this.render(allowed);
    });
  }

  private render(allowed: boolean): void {
    if (allowed && !this.shown) {
      this.container.clear();
      this.fallback = null;
      this.shown = this.container.createEmbeddedView(this.template);
    } else if (!allowed && (this.shown || !this.fallback)) {
      this.container.clear();
      this.shown = null;
      const otherwise = this.hasPermissionElse();
      this.fallback = otherwise ? this.container.createEmbeddedView(otherwise) : null;
    }
  }
}
