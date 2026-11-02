import { ChangeDetectionStrategy, Component, computed, input, output } from '@angular/core';

import { permissionLabel } from '../../core/permission-labels';
import { RoleAdmin } from '../../core/roles-admin.service';
import { MatrixGroup, RolePreview } from './roles-ui';

/**
 * «Probar como este rol»: lo que vería y podría hacer alguien que solo tuviera este rol (menú, alcance
 * de los datos y permisos), sin cambiar nada ni entrar con otra cuenta. Refleja también los cambios
 * sin guardar de la matriz, para comprobar un ajuste antes de aplicarlo.
 */
@Component({
  selector: 'app-role-preview-modal',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="fixed inset-0 z-[55] flex items-end justify-center p-0 sm:items-center sm:p-4">
      <div class="absolute inset-0 bg-brand-navy/50" (click)="closed.emit()" aria-hidden="true"></div>
      <section class="glass relative max-h-[92vh] w-full max-w-2xl overflow-y-auto rounded-t-2xl sm:rounded-2xl" role="dialog" aria-modal="true" aria-labelledby="rp-title">
        <header class="flex items-center justify-between gap-3 border-b border-brand-grey/70 px-5 py-3">
          <div>
            <h2 id="rp-title" class="text-[16px] font-bold text-on-surface">Probar como «{{ role().name }}»</h2>
            <p class="text-[12px] text-on-surface-variant">Esto es lo que vería y podría hacer una persona que solo tenga este rol.@if (unsaved()) { Incluye cambios sin guardar. }</p>
          </div>
          <button type="button" (click)="closed.emit()" aria-label="Cerrar"
            class="rounded-lg bg-transparent p-1 !text-on-surface-variant hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep">
            <span class="material-symbols-outlined text-[20px]" aria-hidden="true">close</span>
          </button>
        </header>

        <div class="space-y-4 px-5 py-4">
          <section aria-labelledby="rp-menu">
            <h3 id="rp-menu" class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Menú que vería</h3>
            <ul class="mt-2 flex flex-wrap gap-2">
              @for (item of preview().menu; track item.path) {
                <li class="inline-flex items-center gap-1.5 rounded-full bg-surface-container px-3 py-1 text-[12px] font-semibold text-on-surface">
                  <span class="material-symbols-outlined text-[16px]" aria-hidden="true">{{ item.icon }}</span>{{ item.label }}
                </li>
              }
            </ul>
          </section>

          <section aria-labelledby="rp-scope">
            <h3 id="rp-scope" class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Datos que vería</h3>
            @if (preview().scopes.length) {
              <dl class="mt-2 grid grid-cols-2 gap-x-4 gap-y-1 text-[13px] sm:grid-cols-4">
                @for (s of preview().scopes; track s.resource) {
                  <div><dt class="text-on-surface-variant">{{ s.label }}</dt><dd class="m-0 font-bold text-on-surface">{{ s.scope }}</dd></div>
                }
              </dl>
            } @else {
              <p class="mt-2 text-[13px] text-on-surface-variant">Este rol no ve datos de operación.</p>
            }
          </section>

          <section aria-labelledby="rp-perms">
            <h3 id="rp-perms" class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Qué puede hacer ({{ preview().codes.length }})</h3>
            @for (group of groups(); track group.resource) {
              <div class="mt-2">
                <p class="text-[12px] font-bold text-on-surface">{{ group.label }}</p>
                <ul class="mt-1 flex flex-wrap gap-1.5">
                  @for (row of group.rows; track row.code) {
                    <li class="rounded-md bg-brand-accentLight px-2 py-0.5 text-[12px] font-semibold text-brand-accentDeep" [title]="label(row.code)">{{ row.actionLabel }}</li>
                  }
                </ul>
              </div>
            } @empty {
              <p class="mt-2 text-[13px] text-on-surface-variant">Este rol no concede ningún permiso.</p>
            }
          </section>
        </div>

        <footer class="flex justify-end border-t border-brand-grey/70 px-5 py-3">
          <button type="button" (click)="closed.emit()"
            class="glass-btn rounded-xl px-5 py-2 text-[13px] font-bold transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep">Cerrar</button>
        </footer>
      </section>
    </div>
  `,
})
export class RolePreviewModalComponent {
  readonly role = input.required<RoleAdmin>();
  readonly preview = input.required<RolePreview>();
  readonly matrix = input<readonly MatrixGroup[]>([]);
  readonly unsaved = input(false);
  readonly closed = output<void>();

  /** Solo los recursos y acciones que el rol tiene, con el orden de la matriz. */
  readonly groups = computed(() => {
    const granted = new Set(this.preview().codes);
    return this.matrix()
      .map((group) => ({ ...group, rows: group.rows.filter((row) => granted.has(row.code)) }))
      .filter((group) => group.rows.length);
  });

  label(code: string): string {
    return permissionLabel(code);
  }
}
