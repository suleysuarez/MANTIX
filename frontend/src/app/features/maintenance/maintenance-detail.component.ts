import { AsyncPipe, DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';

import { LocalProfileService } from '../../core/local-profile.service';
import { MaintenanceDetailStore } from '../../core/maintenance-detail.store';
import { WORK_TYPES } from '../../core/maintenance.service';

/** Smart component: detalle del ticket, cambios de estado, asignación y registros de trabajo. */
@Component({
  standalone: true,
  imports: [AsyncPipe, DatePipe, RouterLink],
  template: `
    <main class="page">
      <a routerLink="/maintenance" class="back">← Back to requests</a>

      @if (state$ | async; as state) {
        @if (state.error) {
          <p class="error" role="alert">{{ state.error }}</p>
        }
        @if (state.loading) {
          <p>Loading request…</p>
        } @else {
          @if (state.request; as request) {
          <header>
            <p class="eyebrow">{{ request.ticket_number }}</p>
            <h1>{{ request.title }}</h1>
            <p>
              <span class="chip">{{ request.status }}</span>
              <span class="chip priority-{{ request.priority }}">{{ request.priority }}</span>
            </p>
          </header>

          <section class="card">
            <p>{{ request.description }}</p>
            <dl>
              <dt>Equipment</dt><dd>{{ request.equipment.asset_tag }} — {{ request.equipment.brand }} {{ request.equipment.model }}</dd>
              <dt>Requested by</dt><dd>{{ request.requested_by.full_name }}</dd>
              <dt>Created</dt><dd>{{ request.created_at | date: 'medium' }}</dd>
              <dt>Technician</dt><dd>{{ request.current_assignment?.technician?.full_name ?? 'Unassigned' }}</dd>
              @if (request.resolution_summary) {
                <dt>Resolution</dt><dd>{{ request.resolution_summary }}</dd>
              }
            </dl>
          </section>

          @if (canManage()) {
            <section class="card">
              <h2>Actions</h2>
              @if (request.allowed_next_statuses.length > 0) {
                <form #transition class="inline" (submit)="changeStatus($event, status.value, notes.value, summary.value)">
                  <label>Move to
                    <select #status>
                      @for (option of request.allowed_next_statuses; track option) {
                        <option [value]="option">{{ option }}</option>
                      }
                    </select>
                  </label>
                  <label>Notes <input #notes /></label>
                  <label>Resolution summary <input #summary placeholder="When resolving" /></label>
                  <button type="submit" [disabled]="state.busy">Change status</button>
                </form>
              } @else {
                <p class="muted">This request is in a final state.</p>
              }

              <form class="inline" (submit)="assign($event, technician.value, assignNotes.value)">
                <label>Technician
                  <select #technician>
                    @for (item of state.technicians; track item.id) {
                      <option [value]="item.id" [disabled]="!item.is_available">
                        #{{ item.id }} {{ item.specialization || 'Technician' }}{{ item.is_available ? '' : ' (unavailable)' }}
                      </option>
                    }
                  </select>
                </label>
                <label>Notes <input #assignNotes /></label>
                <button type="submit" [disabled]="state.busy || state.technicians.length === 0">Assign</button>
                @if (request.current_assignment) {
                  <button type="button" class="secondary" [disabled]="state.busy" (click)="unassign()">Unassign</button>
                }
              </form>
            </section>
          }

          <section class="card">
            <h2>Status history</h2>
            <ol>
              @for (entry of request.status_history; track entry.id) {
                <li>
                  {{ entry.from_status ?? 'start' }} → <strong>{{ entry.to_status }}</strong>
                  <span class="muted"> · {{ entry.changed_at | date: 'short' }}</span>
                  @if (entry.notes) { <span class="muted"> · {{ entry.notes }}</span> }
                </li>
              }
            </ol>
          </section>

          <section class="card">
            <h2>Work records</h2>
            @if (state.records.length === 0) {
              <p class="muted">No work has been recorded yet.</p>
            }
            @for (record of state.records; track record.id) {
              <article class="record">
                <strong>{{ record.work_type }}</strong> · {{ record.result }}
                <p>{{ record.diagnosis }}</p>
                <p class="muted">{{ record.actions_taken }}</p>
                @if (record.total_cost) { <p class="muted">Total cost: {{ record.total_cost }}</p> }
              </article>
            }

            @if (canManage()) {
              <form #recordForm class="stack" (submit)="addRecord($event, recordForm, workType.value, diagnosis.value, actions.value, result.value, labor.value, parts.value)">
                <h3>Add record</h3>
                <label>Work type
                  <select #workType>
                    @for (option of workTypes; track option) { <option [value]="option">{{ option }}</option> }
                  </select>
                </label>
                <label>Diagnosis <textarea #diagnosis required rows="2"></textarea></label>
                <label>Actions taken <textarea #actions required rows="2"></textarea></label>
                <label>Result <input #result required maxlength="50" /></label>
                <label>Labor cost <input #labor type="number" min="0" step="0.01" /></label>
                <label>Parts cost <input #parts type="number" min="0" step="0.01" /></label>
                <button type="submit" [disabled]="state.busy">Save record</button>
              </form>
            }
          </section>
          }
        }
      }
    </main>
  `,
  styles: [
    `.page { max-width: 900px; margin: 2.5rem auto; padding: 0 1.5rem; }
     .back { color: #2563eb; text-decoration: none; }
     .eyebrow { color: #2563eb; font-weight: 700; letter-spacing: .08em; }
     .error { color: #b91c1c; } .muted { color: #64748b; }
     .card { padding: 1.25rem; background: white; border: 1px solid #e2e8f0; border-radius: 10px; margin: 1.25rem 0; }
     dl { display: grid; grid-template-columns: 9rem 1fr; gap: .4rem 1rem; } dt { color: #64748b; } dd { margin: 0; }
     .chip { padding: .15rem .55rem; border-radius: 999px; background: #e2e8f0; font-size: .8rem; margin-right: .4rem; }
     .priority-high { background: #fed7aa; } .priority-critical { background: #fecaca; }
     form { display: flex; gap: .75rem; flex-wrap: wrap; align-items: end; margin-top: 1rem; }
     form.stack { display: grid; }
     label { display: grid; gap: .25rem; font-size: .85rem; color: #475569; }
     input, select, textarea { padding: .5rem .7rem; border: 1px solid #cbd5e1; border-radius: 6px; font: inherit; }
     button { padding: .55rem 1rem; border: 0; border-radius: 6px; background: #0f172a; color: white; cursor: pointer; }
     button.secondary { background: white; color: #0f172a; border: 1px solid #cbd5e1; }
     button:disabled { background: #94a3b8; cursor: default; }
     .record { padding: .75rem 0; border-bottom: 1px solid #e2e8f0; } ol { padding-left: 1.2rem; }`,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class MaintenanceDetailComponent implements OnInit {
  private readonly store = inject(MaintenanceDetailStore);
  private readonly profile = inject(LocalProfileService);
  private readonly route = inject(ActivatedRoute);

  readonly state$ = this.store.state$;
  readonly workTypes = WORK_TYPES;
  readonly canManage = signal(false);

  async ngOnInit(): Promise<void> {
    const id = Number(this.route.snapshot.paramMap.get('id'));
    this.store.load(id);
    this.canManage.set(await this.profile.can('maintenance.manage'));
  }

  changeStatus(event: Event, status: string, notes: string, summary: string): void {
    event.preventDefault();
    this.store.transition(status, notes.trim() || null, summary.trim() || null);
  }

  assign(event: Event, technicianId: string, notes: string): void {
    event.preventDefault();
    if (technicianId) {
      this.store.assign(Number(technicianId), notes.trim() || null);
    }
  }

  unassign(): void {
    this.store.unassign();
  }

  addRecord(
    event: Event,
    form: HTMLFormElement,
    workType: string,
    diagnosis: string,
    actions: string,
    result: string,
    labor: string,
    parts: string,
  ): void {
    event.preventDefault();
    if (!diagnosis.trim() || !actions.trim() || !result.trim()) {
      return;
    }
    this.store.addRecord({
      work_type: workType,
      started_at: new Date().toISOString(),
      completed_at: null,
      diagnosis: diagnosis.trim(),
      actions_taken: actions.trim(),
      result: result.trim(),
      labor_cost: labor ? Number(labor) : null,
      parts_cost: parts ? Number(parts) : null,
      notes: null,
    });
    form.reset();
  }
}
