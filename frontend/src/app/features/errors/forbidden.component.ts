import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { Location } from '@angular/common';
import { map } from 'rxjs';

import { permissionLabel } from '../../core/permission-labels';

/**
 * 403: la sesión es válida pero el rol no permite esta pantalla. Los guards llevan aquí (con el permiso que
 * faltaba en `?requiere=`) en vez de dejar una pantalla en blanco o redirigir sin decir nada.
 */
@Component({
  selector: 'app-forbidden',
  standalone: true,
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section class="tw-reset glass mx-auto mt-6 flex max-w-lg flex-col items-center gap-3 rounded-2xl p-8 text-center" role="alert" aria-labelledby="forbidden-title">
      <svg viewBox="0 0 240 160" width="240" height="160" role="img" aria-label="Candado sobre una pantalla" class="h-auto w-56">
        <rect x="30" y="22" width="180" height="108" rx="12" fill="#ADD7F6" opacity=".55" />
        <rect x="42" y="34" width="156" height="84" rx="8" fill="#F7FAFC" />
        <rect x="54" y="46" width="64" height="8" rx="4" fill="#CED4DA" />
        <rect x="54" y="62" width="104" height="8" rx="4" fill="#CED4DA" />
        <rect x="54" y="78" width="84" height="8" rx="4" fill="#CED4DA" />
        <rect x="100" y="132" width="40" height="8" rx="4" fill="#778DA9" />
        <circle cx="168" cy="96" r="30" fill="#3E5C76" />
        <path d="M156 94v-6a12 12 0 0 1 24 0v6" fill="none" stroke="#ADD7F6" stroke-width="5" stroke-linecap="round" />
        <rect x="152" y="94" width="32" height="24" rx="5" fill="#D4A017" />
        <circle cx="168" cy="104" r="3.5" fill="#3E5C76" />
        <rect x="166.5" y="104" width="3" height="8" rx="1.5" fill="#3E5C76" />
      </svg>
      <p class="text-[12px] font-bold uppercase tracking-wider text-on-surface-variant">Error 403</p>
      <h1 id="forbidden-title" class="text-[22px] font-bold text-on-surface">No tienes permiso para ver esta pantalla</h1>
      <p class="text-[14px] text-on-surface-variant">
        Tu rol no incluye este módulo.
        @if (required(); as code) { <span class="block">Hace falta el permiso: <strong class="text-on-surface">{{ label(code) }}</strong>.</span> }
        Si crees que es un error, pide acceso a un administrador.
      </p>
      <div class="mt-2 flex flex-wrap justify-center gap-2">
        <button type="button" (click)="back()" class="rounded-xl border border-brand-grey bg-transparent px-5 py-2 text-[13px] font-bold !text-brand-accentDeep hover:bg-surface-container-high focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep">Volver</button>
        <a routerLink="/dashboard" class="glass-btn rounded-xl px-5 py-2 text-[13px] font-bold">Ir al dashboard</a>
      </div>
    </section>
  `,
})
export class ForbiddenComponent {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly location = inject(Location);

  readonly required = toSignal(this.route.queryParamMap.pipe(map((params) => params.get('requiere'))), { initialValue: null });
  readonly label = permissionLabel;
  canGoBack(): boolean {
    return typeof history !== 'undefined' && history.length > 1;
  }

  /** Vuelve a donde estaba la persona; si no hay historial (abrió el enlace directo), al dashboard. */
  back(): void {
    if (this.canGoBack()) {
      this.location.back();
    } else {
      void this.router.navigateByUrl('/dashboard');
    }
  }
}
