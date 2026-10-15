import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouterLink } from '@angular/router';

/** 403: la sesión es válida pero el rol no permite esta pantalla. Los guards redirigen aquí en vez de no hacer nada. */
@Component({
  selector: 'app-forbidden',
  standalone: true,
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section class="tw-reset glass mx-auto mt-10 flex max-w-md flex-col items-center gap-3 rounded-2xl p-8 text-center" role="alert" aria-labelledby="forbidden-title">
      <span class="flex h-14 w-14 items-center justify-center rounded-full bg-brand-accentLight/60 text-brand-accentDeep">
        <span class="material-symbols-outlined text-[30px]" aria-hidden="true">lock</span>
      </span>
      <p class="text-[12px] font-bold uppercase tracking-wider text-on-surface-variant">Error 403</p>
      <h1 id="forbidden-title" class="text-[20px] font-bold text-on-surface">No tienes permiso para ver esta pantalla</h1>
      <p class="text-[14px] text-on-surface-variant">Tu rol no incluye este módulo. Si crees que es un error, pide acceso a un administrador.</p>
      <a routerLink="/dashboard" class="glass-btn mt-2 rounded-xl px-5 py-2 text-[13px] font-bold">Volver al dashboard</a>
    </section>
  `,
})
export class ForbiddenComponent {}
