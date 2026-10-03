import { AsyncPipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';

import { LocalProfileService } from '../../core/local-profile.service';
import { TechniciansStore } from '../../core/technicians.store';

/** Smart component: perfiles de técnicos y su disponibilidad. */
@Component({
  standalone: true,
  imports: [AsyncPipe],
  template: `
    @if (state$ | async; as state) {
      <main class="page">
        <header>
          <p class="eyebrow">Maintenance</p>
          <h1>Technicians</h1>
        </header>

        @if (state.error) {
          <p class="error" role="alert">{{ state.error }}</p>
        }

        @if (canManage()) {
          <form #form class="card" (submit)="create($event, form, userId.value, specialization.value, rate.value)">
            <h2>New technician profile</h2>
            <label>User ID <input #userId type="number" min="1" required /></label>
            <label>Specialization <input #specialization maxlength="100" /></label>
            <label>Hourly rate <input #rate type="number" min="0" step="0.01" /></label>
            <button type="submit" [disabled]="state.saving">{{ state.saving ? 'Saving…' : 'Create profile' }}</button>
          </form>
        }

        @if (state.loading) {
          <p>Loading technicians…</p>
        } @else if (state.technicians.length === 0) {
          <p class="card">There are no technician profiles yet.</p>
        } @else {
          <div class="card table-wrap">
            <table>
              <thead><tr><th>ID</th><th>User</th><th>Specialization</th><th>Rate</th><th>Available</th></tr></thead>
              <tbody>
                @for (item of state.technicians; track item.id) {
                  <tr>
                    <td>{{ item.id }}</td>
                    <td>{{ item.user_id }}</td>
                    <td>{{ item.specialization || '—' }}</td>
                    <td>{{ item.hourly_rate || '—' }}</td>
                    <td>
                      @if (canManage()) {
                        <input type="checkbox" [checked]="item.is_available" [attr.aria-label]="'Available: technician ' + item.id" (change)="toggle(item.id, $any($event.target).checked)" />
                      } @else {
                        {{ item.is_available ? 'Yes' : 'No' }}
                      }
                    </td>
                  </tr>
                }
              </tbody>
            </table>
          </div>
        }
      </main>
    }
  `,
  styles: [
    `.page { max-width: 900px; margin: 3rem auto; padding: 0 1.5rem; }
     .eyebrow { color: #2563eb; font-weight: 700; text-transform: uppercase; letter-spacing: .08em; }
     .error { color: #b91c1c; }
     .card { display: grid; gap: .75rem; padding: 1.25rem; background: white; border: 1px solid #e2e8f0; border-radius: 10px; margin: 1.25rem 0; }
     .table-wrap { overflow-x: auto; } table { width: 100%; border-collapse: collapse; }
     th, td { padding: .7rem; text-align: left; border-bottom: 1px solid #e2e8f0; }
     label { display: grid; gap: .25rem; font-size: .85rem; color: #475569; }
     input:not([type='checkbox']) { padding: .5rem .7rem; border: 1px solid #cbd5e1; border-radius: 6px; font: inherit; }
     button { padding: .55rem 1rem; border: 0; border-radius: 6px; background: #0f172a; color: white; cursor: pointer; justify-self: start; }
     button:disabled { background: #94a3b8; cursor: default; }`,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class TechniciansComponent implements OnInit {
  private readonly store = inject(TechniciansStore);
  private readonly profile = inject(LocalProfileService);

  readonly state$ = this.store.state$;
  readonly canManage = signal(false);

  async ngOnInit(): Promise<void> {
    this.store.load();
    this.canManage.set(await this.profile.can('technicians.manage'));
  }

  create(event: Event, form: HTMLFormElement, userId: string, specialization: string, rate: string): void {
    event.preventDefault();
    if (!userId) {
      return;
    }
    this.store.create({
      user_id: Number(userId),
      specialization: specialization.trim() || null,
      hourly_rate: rate ? Number(rate) : null,
    });
    form.reset();
  }

  toggle(id: number, isAvailable: boolean): void {
    this.store.setAvailability(id, isAvailable);
  }
}
