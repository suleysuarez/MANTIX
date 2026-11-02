import { ChangeDetectionStrategy, Component, ElementRef, HostListener, OnInit, computed, inject, input, output, signal, viewChild } from '@angular/core';

import { ManagedAccount } from '../../core/users.service';
import { UsersStore } from '../../core/users.store';
import { USER_LIMITS, passwordError } from './users-ui';

const FIELD =
  'mt-1 w-full rounded-lg border border-outline bg-surface-container-lowest px-3 py-2 text-[13px] text-on-surface focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep aria-[invalid=true]:border-error';

/** Fija una contraseña nueva para otra persona. Nunca se muestra ni se guarda en Mantix. */
@Component({
  selector: 'app-password-modal',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="fixed inset-0 z-[55] flex items-end justify-center p-0 sm:items-center sm:p-4">
      <div class="absolute inset-0 bg-brand-navy/50" (click)="closed.emit()" aria-hidden="true"></div>
      <form class="glass relative w-full max-w-md rounded-t-2xl sm:rounded-2xl" role="dialog" aria-modal="true" aria-labelledby="pw-title"
        (submit)="submit($event)" novalidate>
        <header class="flex items-center justify-between gap-3 border-b border-brand-grey/70 px-5 py-3">
          <h2 id="pw-title" class="text-[16px] font-bold text-on-surface">Restablecer contraseña</h2>
          <button type="button" (click)="closed.emit()" aria-label="Cerrar"
            class="rounded-lg bg-transparent p-1 !text-on-surface-variant hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep">
            <span class="material-symbols-outlined text-[20px]" aria-hidden="true">close</span>
          </button>
        </header>
        <div class="space-y-3 px-5 py-4">
          <p class="text-[13px] text-on-surface-variant">
            Nueva contraseña para <strong class="text-on-surface">{{ user().full_name }}</strong>. Compártela por un canal seguro: Mantix no la guarda.
          </p>
          <div>
            <label for="pw-new" class="text-[12px] font-bold text-on-surface">Nueva contraseña *</label>
            <input #firstField id="pw-new" type="password" autocomplete="new-password" [class]="field" [attr.maxlength]="limits.passwordMax"
              [value]="password()" (input)="password.set($any($event.target).value)" [attr.aria-invalid]="!!shownError()" aria-describedby="pw-hint pw-err" />
            <p id="pw-hint" class="mt-1 text-[12px] text-on-surface-variant">Mínimo {{ limits.passwordMin }} caracteres, con mayúsculas, minúsculas y números, sin espacios.</p>
          </div>
          <div>
            <label for="pw-confirm" class="text-[12px] font-bold text-on-surface">Confirmar contraseña *</label>
            <input id="pw-confirm" type="password" autocomplete="new-password" [class]="field" [attr.maxlength]="limits.passwordMax"
              [value]="confirmation()" (input)="confirmation.set($any($event.target).value)" [attr.aria-invalid]="!!shownError()" />
          </div>
          <p id="pw-err" class="min-h-[1rem] text-[12px] text-error" role="alert">{{ shownError() }}</p>
        </div>
        <footer class="flex justify-end gap-2 border-t border-brand-grey/70 px-5 py-3">
          <button type="button" (click)="closed.emit()" [disabled]="busy()"
            class="rounded-lg bg-transparent px-4 py-2 text-[13px] font-semibold !text-on-surface-variant hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep">Cancelar</button>
          <button type="submit" [disabled]="busy()"
            class="glass-btn rounded-xl px-5 py-2 text-[13px] font-bold transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep">
            {{ busy() ? 'Guardando…' : 'Restablecer' }}
          </button>
        </footer>
      </form>
    </div>
  `,
})
export class PasswordModalComponent implements OnInit {
  private readonly store = inject(UsersStore);

  readonly user = input.required<ManagedAccount>();
  readonly busy = input(false);
  readonly closed = output<void>();

  readonly firstField = viewChild<ElementRef<HTMLInputElement>>('firstField');
  readonly field = FIELD;
  readonly limits = USER_LIMITS;
  readonly password = signal('');
  readonly confirmation = signal('');
  private readonly submitted = signal(false);
  private readonly serverError = signal('');

  readonly error = computed(() => passwordError(this.password(), this.confirmation()));
  readonly shownError = computed(() => this.serverError() || (this.submitted() ? this.error() : ''));

  @HostListener('document:keydown.escape')
  onEscape(): void {
    this.closed.emit();
  }

  ngOnInit(): void {
    setTimeout(() => this.firstField()?.nativeElement.focus());
  }

  submit(event: Event): void {
    event.preventDefault();
    this.submitted.set(true);
    this.serverError.set('');
    if (this.error() || this.busy()) {
      return;
    }
    this.store.resetPassword(this.user().id, this.password()).subscribe((result) => {
      if (result.ok) {
        this.closed.emit();
      } else {
        this.serverError.set(result.fieldErrors['password'] ?? 'No se pudo restablecer la contraseña. Revisa que cumpla la política.');
      }
    });
  }
}
