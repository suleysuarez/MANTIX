import { ChangeDetectionStrategy, Component } from '@angular/core';

/**
 * Se muestra cuando una pantalla no se pudo descargar (típico tras un despliegue: el navegador
 * guarda una versión vieja que apunta a archivos que ya no existen). Va fuera del shell y sin
 * carga diferida, para que funcione justo cuando lo demás falla.
 */
@Component({
  selector: 'app-load-error',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <main class="tw-reset mx-auto mt-24 flex max-w-md flex-col items-center gap-3 rounded-2xl bg-white p-8 text-center shadow-lg" role="alert">
      <span class="material-symbols-outlined text-[36px] text-[#3E5C76]" aria-hidden="true">cloud_off</span>
      <h1 class="text-[20px] font-bold text-[#1E293B]">No se pudo abrir esta pantalla</h1>
      <p class="text-[14px] text-[#64748B]">Probablemente hay una versión nueva de la aplicación. Recarga la página para actualizarla.</p>
      <button type="button" (click)="reload()" class="glass-btn mt-2 rounded-xl px-5 py-2 text-[13px] font-bold">Recargar</button>
    </main>
  `,
})
export class LoadErrorComponent {
  reload(): void {
    location.reload();
  }
}
