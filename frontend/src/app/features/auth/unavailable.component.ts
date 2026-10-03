import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { Router } from '@angular/router';

import { ClerkService } from '../../core/clerk.service';

/** Se muestra cuando hay sesión de Clerk pero el backend no responde. */
@Component({
  standalone: true,
  template: `
    <div class="tw-reset grid min-h-screen place-items-center bg-surface-variant p-space-md font-sans">
      <section class="flex w-full max-w-md flex-col items-center gap-space-md rounded-[28px] bg-surface-container-lowest p-space-xl text-center shadow-[0_12px_36px_-6px_rgba(38,68,93,0.14)]">
        <img src="assets/images/logo.png" alt="MANTIX" class="h-24 w-24 object-contain" />
        <span class="material-symbols-outlined text-[36px] text-secondary">cloud_off</span>
        <h1 class="font-headline-lg text-headline-lg text-primary">No pudimos conectar con el servidor</h1>
        <p class="font-body-md text-body-md text-on-surface-variant">
          Tu sesión es válida, pero la API de MANTIX no responde. Verifica que el backend esté en
          ejecución e inténtalo de nuevo.
        </p>
        <div class="flex gap-space-sm pt-2">
          <button type="button" (click)="retry()"
            class="h-11 rounded-xl bg-secondary-container px-space-lg font-headline-sm text-headline-sm text-on-secondary-container">
            Reintentar
          </button>
          <button type="button" (click)="signOut()"
            class="h-11 rounded-xl bg-surface-container-low px-space-lg font-headline-sm text-headline-sm text-primary">
            Cerrar sesión
          </button>
        </div>
      </section>
    </div>
  `,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class UnavailableComponent {
  private readonly router = inject(Router);
  private readonly clerk = inject(ClerkService);

  retry(): void {
    void this.router.navigateByUrl('/dashboard');
  }

  async signOut(): Promise<void> {
    await this.clerk.signOut();
  }
}
