import { ChangeDetectionStrategy, Component, inject } from '@angular/core';

import { ToastKind, ToastService } from '../core/toast.service';

/** Clases por tipo; todas con contraste de texto AA sobre su fondo. */
const TONE: Record<ToastKind, string> = {
  success: 'bg-brand-accentDeep text-on-primary',
  error: 'bg-error-container text-on-error-container',
  info: 'bg-brand-accentLight text-brand-accentDeep',
};
const ICON: Record<ToastKind, string> = { success: 'check_circle', error: 'error', info: 'info' };

/** Pinta los avisos de `ToastService`; una pantalla lo incluye una vez. */
@Component({
  selector: 'app-toast-host',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="pointer-events-none fixed bottom-4 right-4 z-[60] flex w-[min(24rem,calc(100vw-2rem))] flex-col gap-2" aria-live="polite">
      @for (toast of toasts.toasts(); track toast.id) {
        <div class="pointer-events-auto flex items-start gap-3 rounded-xl px-4 py-3 shadow-lg" [class]="tone[toast.kind]"
          [attr.role]="toast.kind === 'error' ? 'alert' : 'status'">
          <span class="material-symbols-outlined text-[20px]" aria-hidden="true">{{ icon[toast.kind] }}</span>
          <p class="min-w-0 flex-1 text-[13px] font-medium leading-5">{{ toast.message }}</p>
          <button type="button" (click)="toasts.dismiss(toast.id)" aria-label="Cerrar aviso"
            class="rounded p-0.5 opacity-80 hover:opacity-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-current">
            <span class="material-symbols-outlined text-[18px]" aria-hidden="true">close</span>
          </button>
        </div>
      }
    </div>
  `,
})
export class ToastHostComponent {
  readonly toasts = inject(ToastService);
  readonly tone = TONE;
  readonly icon = ICON;
}
