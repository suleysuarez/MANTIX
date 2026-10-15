import {
  ChangeDetectionStrategy,
  Component,
  EventEmitter,
  Input,
  Output,
} from '@angular/core';

import { AdminRole, PendingUser } from '../../core/admin-users.service';

/** Dumb component: one pending user; role selection is local UI state only. */
@Component({
  selector: 'app-pending-user-card',
  standalone: true,
  template: `
    <article class="user-card">
      <div>
        <h2>{{ user.full_name }}</h2>
        <p>{{ user.email }}</p>
      </div>
      <fieldset>
        <legend>Roles</legend>
        @for (role of roles; track role.id) {
          <label>
            <input
              type="checkbox"
              [checked]="selected.has(role.id)"
              (change)="toggle(role.id, $any($event.target).checked)"
            />
            {{ role.name }} ({{ role.code }})
          </label>
        }
      </fieldset>
      <button type="button" [disabled]="saving || selected.size === 0" (click)="submit()">
        {{ saving ? 'Assigning…' : 'Assign roles' }}
      </button>
    </article>
  `,
  styles: [
    `.user-card { display: grid; gap: 1rem; padding: 1.5rem; background: white; border: 1px solid #e2e8f0; border-radius: 10px; }
     h2, p { margin: 0; } fieldset { border: 0; padding: 0; display: flex; flex-wrap: wrap; gap: .8rem 1.2rem; }
     label { display: flex; gap: .4rem; align-items: center; }
     button { width: fit-content; padding: .65rem 1rem; border: 0; border-radius: 6px; background: #0f172a; color: white; cursor: pointer; }
     button:disabled { cursor: not-allowed; opacity: .5; }`,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PendingUserCardComponent {
  @Input({ required: true }) user!: PendingUser;
  @Input() roles: readonly AdminRole[] = [];
  @Input() saving = false;
  @Output() readonly assign = new EventEmitter<number[]>();

  selected = new Set<number>();

  submit(): void {
    this.assign.emit([...this.selected]);
  }

  toggle(roleId: number, checked: boolean): void {
    const next = new Set(this.selected);
    if (checked) {
      next.add(roleId);
    } else {
      next.delete(roleId);
    }
    this.selected = next;
  }
}
