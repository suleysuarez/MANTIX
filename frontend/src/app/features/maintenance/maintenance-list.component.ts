import { AsyncPipe, DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { RouterLink } from '@angular/router';

import { LocalProfileService } from '../../core/local-profile.service';
import { PRIORITIES, REQUEST_STATUSES } from '../../core/maintenance.service';
import { MaintenanceStore } from '../../core/maintenance.store';

/** Smart component: filtros, paginación y alta de solicitudes de mantenimiento. */
@Component({
  standalone: true,
  imports: [AsyncPipe, DatePipe, RouterLink],
  template: `
    @if (state$ | async; as state) {
      <main class="page">
        <header>
          <p class="eyebrow">Maintenance</p>
          <h1>Maintenance requests</h1>
          <p>Track incidents and repairs for technology equipment.</p>
        </header>

        @if (state.error) {
          <p class="error" role="alert">{{ state.error }}</p>
        }

        @if (canCreate()) {
          <form #form class="card" (submit)="submit($event, form, equipment.value, title.value, description.value, priority.value)">
            <h2>New request</h2>
            <label>Equipment
              <select #equipment required>
                <option value="" disabled selected>Select equipment</option>
                @for (item of state.equipment; track item.id) {
                  <option [value]="item.id">{{ item.asset_tag }} — {{ item.brand }} {{ item.model }}</option>
                }
              </select>
            </label>
            <label>Title <input #title required maxlength="200" /></label>
            <label>Description <textarea #description required rows="3"></textarea></label>
            <label>Priority
              <select #priority>
                @for (option of priorities; track option) {
                  <option [value]="option" [selected]="option === 'medium'">{{ option }}</option>
                }
              </select>
            </label>
            <button type="submit" [disabled]="state.saving">{{ state.saving ? 'Saving…' : 'Create request' }}</button>
          </form>
        }

        <section>
          <h2>Requests</h2>
          <div class="filters">
            <label>Status
              <select #statusFilter (change)="filter(statusFilter.value, priorityFilter.value)">
                <option value="">All</option>
                @for (option of statuses; track option) {
                  <option [value]="option" [selected]="option === state.status">{{ option }}</option>
                }
              </select>
            </label>
            <label>Priority
              <select #priorityFilter (change)="filter(statusFilter.value, priorityFilter.value)">
                <option value="">All</option>
                @for (option of priorities; track option) {
                  <option [value]="option" [selected]="option === state.priority">{{ option }}</option>
                }
              </select>
            </label>
          </div>

          @if (state.loading) {
            <p>Loading requests…</p>
          } @else if (state.items.length === 0) {
            <p class="empty">No maintenance requests match the current filters.</p>
          } @else {
            <div class="table-wrap">
              <table>
                <thead><tr><th>Ticket</th><th>Title</th><th>Priority</th><th>Status</th><th>Created</th></tr></thead>
                <tbody>
                  @for (item of state.items; track item.id) {
                    <tr>
                      <td><a [routerLink]="['/maintenance', item.id]">{{ item.ticket_number }}</a></td>
                      <td>{{ item.title }}</td>
                      <td><span class="chip priority-{{ item.priority }}">{{ item.priority }}</span></td>
                      <td>{{ item.status }}</td>
                      <td>{{ item.created_at | date: 'short' }}</td>
                    </tr>
                  }
                </tbody>
              </table>
            </div>
          }

          <nav class="pager" aria-label="Request pages">
            <button type="button" [disabled]="state.page === 0 || state.loading" (click)="page(state.page - 1)">Previous</button>
            <span>Page {{ state.page + 1 }}</span>
            <button type="button" [disabled]="!state.hasNext || state.loading" (click)="page(state.page + 1)">Next</button>
          </nav>
        </section>
      </main>
    }
  `,
  styles: [
    `.page { max-width: 1100px; margin: 3rem auto; padding: 0 1.5rem; }
     .eyebrow { color: #2563eb; font-weight: 700; text-transform: uppercase; letter-spacing: .08em; }
     .error { color: #b91c1c; }
     .card { display: grid; gap: .75rem; padding: 1.25rem; background: white; border: 1px solid #e2e8f0; border-radius: 10px; margin: 1.5rem 0; }
     label { display: grid; gap: .25rem; font-size: .85rem; color: #475569; }
     input, select, textarea { padding: .5rem .7rem; border: 1px solid #cbd5e1; border-radius: 6px; font: inherit; }
     button { padding: .55rem 1rem; border: 0; border-radius: 6px; background: #0f172a; color: white; cursor: pointer; justify-self: start; }
     button:disabled { background: #94a3b8; cursor: default; }
     .filters { display: flex; gap: 1rem; flex-wrap: wrap; margin: 1rem 0; }
     .empty, .table-wrap { margin: 1rem 0; padding: 1.25rem; background: white; border: 1px solid #e2e8f0; border-radius: 10px; }
     .table-wrap { overflow-x: auto; } table { width: 100%; border-collapse: collapse; }
     th, td { padding: .7rem; text-align: left; border-bottom: 1px solid #e2e8f0; }
     .chip { padding: .15rem .55rem; border-radius: 999px; background: #e2e8f0; font-size: .8rem; }
     .priority-high { background: #fed7aa; } .priority-critical { background: #fecaca; }
     .pager { display: flex; align-items: center; gap: 1rem; }
     .pager button { background: white; color: #0f172a; border: 1px solid #cbd5e1; }`,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class MaintenanceListComponent implements OnInit {
  private readonly store = inject(MaintenanceStore);
  private readonly profile = inject(LocalProfileService);
  private readonly destroyRef = inject(DestroyRef);

  readonly state$ = this.store.state$;
  readonly priorities = PRIORITIES;
  readonly statuses = REQUEST_STATUSES;
  readonly canCreate = signal(false);

  async ngOnInit(): Promise<void> {
    this.store.requestCreated$.pipe(takeUntilDestroyed(this.destroyRef)).subscribe(() => this.resetForm());
    this.store.load();
    this.canCreate.set(await this.profile.can('maintenance.create'));
  }

  private formRef: HTMLFormElement | null = null;

  submit(
    event: Event,
    form: HTMLFormElement,
    equipmentId: string,
    title: string,
    description: string,
    priority: string,
  ): void {
    event.preventDefault();
    this.formRef = form;
    if (!equipmentId || !title.trim() || !description.trim()) {
      return;
    }
    this.store.create({
      equipment_id: Number(equipmentId),
      title: title.trim(),
      description: description.trim(),
      priority,
    });
  }

  filter(status: string, priority: string): void {
    this.store.setFilters(status, priority);
  }

  page(page: number): void {
    this.store.setPage(page);
  }

  private resetForm(): void {
    this.formRef?.reset();
  }
}
