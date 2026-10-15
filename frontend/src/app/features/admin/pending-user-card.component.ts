import { ChangeDetectionStrategy, Component, computed, input, output, signal } from '@angular/core';

import { AdminRole, PendingUser } from '../../core/admin-users.service';
import { initials } from '../../core/equipment-status';

const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';

/** Una persona que ya entró pero aún no tiene permisos: se le eligen uno o más roles. */
@Component({
  selector: 'app-pending-user-card',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <article class="glass flex flex-col gap-4 rounded-2xl p-5" [attr.aria-label]="'Autorizar a ' + user().full_name">
      <div class="flex items-center gap-3">
        <span class="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-[linear-gradient(135deg,#ADD7F6,#A2D2FF)] text-[16px] font-bold text-[#3E5C76]" aria-hidden="true">{{ initialsOf(user().full_name) }}</span>
        <div class="min-w-0">
          <h2 class="truncate text-[15px] font-bold text-on-surface">{{ user().full_name }}</h2>
          <p class="truncate text-[12px] text-on-surface-variant">{{ user().email }}</p>
        </div>
        <span class="ml-auto shrink-0 rounded-full bg-[#FEF3C7] px-2.5 py-1 text-[11px] font-bold text-[#92400E]">Sin permisos</span>
      </div>

      <fieldset>
        <legend class="mb-2 text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Roles que tendrá</legend>
        <div class="flex flex-wrap gap-2">
          @for (role of roles(); track role.id) {
            <label class="cursor-pointer">
              <input type="checkbox" class="peer sr-only" [checked]="selected().has(role.id)" (change)="toggle(role.id, $any($event.target).checked)" />
              <span class="flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-[13px] font-semibold transition-colors peer-focus-visible:outline peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-brand-accentDeep"
                [class]="selected().has(role.id) ? 'border-brand-accentDeep bg-brand-accentDeep !text-white' : 'border-outline bg-surface-container-lowest !text-on-surface hover:bg-surface-container'">
                <span class="material-symbols-outlined text-[16px]" aria-hidden="true">{{ selected().has(role.id) ? 'check_circle' : 'radio_button_unchecked' }}</span>{{ role.name }}
              </span>
            </label>
          }
        </div>
      </fieldset>

      <div class="flex items-center justify-between gap-3">
        <p class="text-[12px] text-on-surface-variant" role="status">{{ hint() }}</p>
        <button type="button" [disabled]="saving() || selected().size === 0" (click)="submit()"
          class="glass-btn shrink-0 rounded-xl px-5 py-2 text-[13px] font-bold transition-colors {{ focus }}">
          {{ saving() ? 'Asignando…' : 'Asignar roles' }}
        </button>
      </div>
    </article>
  `,
})
export class PendingUserCardComponent {
  readonly user = input.required<PendingUser>();
  readonly roles = input<readonly AdminRole[]>([]);
  readonly saving = input(false);
  readonly assign = output<number[]>();

  readonly focus = FOCUS;
  readonly initialsOf = initials;
  readonly selected = signal<ReadonlySet<number>>(new Set());
  readonly hint = computed(() => {
    const count = this.selected().size;
    return count === 0 ? 'Elige al menos un rol para autorizarla.' : `${count} ${count === 1 ? 'rol elegido' : 'roles elegidos'}.`;
  });

  toggle(roleId: number, checked: boolean): void {
    const next = new Set(this.selected());
    if (checked) {
      next.add(roleId);
    } else {
      next.delete(roleId);
    }
    this.selected.set(next);
  }

  submit(): void {
    if (this.selected().size > 0) {
      this.assign.emit([...this.selected()]);
    }
  }
}
