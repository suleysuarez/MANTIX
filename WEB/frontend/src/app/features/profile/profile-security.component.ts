import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, OnInit, computed, inject, signal } from '@angular/core';

import { ClerkService } from '../../core/clerk.service';
import { ClerkSession } from '../../core/clerk.types';
import { ProfileStore } from '../../core/profile.store';
import { PROFILE_LIMITS, newPasswordError } from './profile-ui';

export interface SessionRow {
  session: ClerkSession;
  device: string;
  location: string;
  isMobile: boolean;
  isCurrent: boolean;
  lastActiveAt: Date | null;
}

const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';
const FIELD = `mt-1 w-full rounded-lg border border-outline bg-surface-container-lowest px-3 py-2 text-[13px] text-on-surface ${FOCUS} aria-[invalid=true]:border-error`;

/** Seguridad: cambio de contraseña (con la actual) y dispositivos con la sesión abierta. */
@Component({
  selector: 'app-profile-security',
  standalone: true,
  imports: [DatePipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
      <form class="glass space-y-3 rounded-2xl p-5" aria-labelledby="ps-pw-title" (submit)="submitPassword($event)" novalidate>
        <div>
          <h2 id="ps-pw-title" class="text-[16px] font-bold text-on-surface">Cambiar contraseña</h2>
          <p class="text-[12px] text-on-surface-variant">Necesitas tu contraseña actual. Tus otros dispositivos siguen abiertos hasta que los cierres.</p>
        </div>
        <div>
          <label for="ps-current" class="text-[12px] font-bold text-on-surface">Contraseña actual *</label>
          <input id="ps-current" type="password" autocomplete="current-password" [class]="field" [attr.maxlength]="limits.passwordMax"
            [value]="current()" (input)="current.set($any($event.target).value)" [attr.aria-invalid]="!!currentError()" aria-describedby="ps-current-err" />
          <p id="ps-current-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ currentError() }}</p>
        </div>
        <div>
          <label for="ps-new" class="text-[12px] font-bold text-on-surface">Nueva contraseña *</label>
          <input id="ps-new" type="password" autocomplete="new-password" [class]="field" [attr.maxlength]="limits.passwordMax"
            [value]="next()" (input)="next.set($any($event.target).value)" [attr.aria-invalid]="!!newError()" aria-describedby="ps-new-hint ps-new-err" />
          <p id="ps-new-hint" class="mt-1 text-[12px] text-on-surface-variant">Mínimo {{ limits.passwordMin }} caracteres, con mayúsculas, minúsculas y números, sin espacios.</p>
        </div>
        <div>
          <label for="ps-confirm" class="text-[12px] font-bold text-on-surface">Confirmar contraseña *</label>
          <input id="ps-confirm" type="password" autocomplete="new-password" [class]="field" [attr.maxlength]="limits.passwordMax"
            [value]="confirmation()" (input)="confirmation.set($any($event.target).value)" [attr.aria-invalid]="!!newError()" />
          <p id="ps-new-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ newError() }}</p>
        </div>
        <button type="submit" [disabled]="busy()"
          class="glass-btn rounded-xl px-5 py-2 text-[13px] font-bold transition-colors {{ focus }}">{{ busy() ? 'Guardando…' : 'Cambiar contraseña' }}</button>
      </form>

      <section class="glass rounded-2xl p-5" aria-labelledby="ps-sessions-title">
        <div class="mb-3 flex items-center justify-between gap-3">
          <div>
            <h2 id="ps-sessions-title" class="text-[16px] font-bold text-on-surface">Sesiones activas</h2>
            <p class="text-[12px] text-on-surface-variant">Dispositivos donde tu cuenta tiene la sesión abierta. Cierra las que no reconozcas.</p>
          </div>
          <button type="button" (click)="loadSessions()"
            class="flex h-9 items-center gap-1 rounded-full bg-surface-container px-4 text-[12px] font-medium !text-on-surface hover:bg-surface-container-high {{ focus }}">
            <span class="material-symbols-outlined text-[16px]" aria-hidden="true">refresh</span> Actualizar
          </button>
        </div>
        @if (sessionsError()) {
          <p role="alert" class="rounded-xl bg-error-container p-3 text-[13px] text-on-error-container">{{ sessionsError() }}</p>
        }
        @if (loadingSessions()) {
          <p class="py-6 text-center text-[13px] text-on-surface-variant" role="status">Cargando sesiones…</p>
        } @else if (rows().length === 0 && !sessionsError()) {
          <p class="py-6 text-center text-[13px] text-on-surface-variant">No se encontraron sesiones activas.</p>
        }
        <ul class="flex flex-col gap-2">
          @for (row of rows(); track row.session.id) {
            <li class="flex items-center gap-3 rounded-[14px] bg-surface-container-low p-3">
              <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-[#DBEAFE] text-[#1E40AF]" aria-hidden="true">
                <span class="material-symbols-outlined text-[22px]">{{ row.isMobile ? 'smartphone' : 'computer' }}</span>
              </span>
              <div class="min-w-0 flex-1">
                <p class="flex items-center gap-2 truncate text-[13px] font-semibold text-on-surface">
                  {{ row.device }}
                  @if (row.isCurrent) { <span class="rounded-full bg-[#D1FAE5] px-2 py-0.5 text-[10px] font-bold text-[#065F46]">ESTA SESIÓN</span> }
                </p>
                <p class="truncate text-[12px] text-on-surface-variant">
                  {{ row.location }}@if (row.lastActiveAt) { · Última actividad {{ row.lastActiveAt | date: 'd MMM y, HH:mm' }} }
                </p>
              </div>
              @if (!row.isCurrent) {
                <button type="button" (click)="revoke(row)" [disabled]="busyId() === row.session.id"
                  class="h-9 shrink-0 rounded-full border border-[#FECACA] bg-transparent px-4 text-[12px] font-medium !text-[#B91C1C] hover:bg-[#FEF2F2] disabled:opacity-50 {{ focus }}">
                  {{ busyId() === row.session.id ? 'Cerrando…' : 'Cerrar sesión' }}
                </button>
              }
            </li>
          }
        </ul>
      </section>
    </div>
  `,
})
export class ProfileSecurityComponent implements OnInit {
  private readonly clerk = inject(ClerkService);
  private readonly store = inject(ProfileStore);

  readonly focus = FOCUS;
  readonly field = FIELD;
  readonly limits = PROFILE_LIMITS;

  readonly current = signal('');
  readonly next = signal('');
  readonly confirmation = signal('');
  readonly busy = signal(false);
  private readonly submitted = signal(false);

  readonly newErrorText = computed(() => newPasswordError(this.current(), this.next(), this.confirmation()));
  readonly currentError = computed(() => (this.submitted() && !this.current() ? 'Escribe tu contraseña actual.' : ''));
  readonly newError = computed(() => (this.submitted() ? this.newErrorText() : ''));

  readonly rows = signal<SessionRow[]>([]);
  readonly loadingSessions = signal(true);
  readonly sessionsError = signal('');
  readonly busyId = signal<string | null>(null);

  ngOnInit(): void {
    void this.loadSessions();
  }

  submitPassword(event: Event): void {
    event.preventDefault();
    this.submitted.set(true);
    if (!this.current() || this.newErrorText() || this.busy()) {
      return;
    }
    this.busy.set(true);
    this.store.changePassword(this.current(), this.next()).subscribe((result) => {
      this.busy.set(false);
      if (result.ok) {
        this.current.set('');
        this.next.set('');
        this.confirmation.set('');
        this.submitted.set(false);
      }
      // Si falla (p. ej. contraseña actual incorrecta) el aviso ya salió como mensaje emergente.
    });
  }

  async loadSessions(): Promise<void> {
    this.loadingSessions.set(true);
    this.sessionsError.set('');
    try {
      const { sessions, currentId } = await this.clerk.getActiveSessions();
      this.rows.set(sessions.map((session) => toRow(session, currentId)).sort((a, b) => Number(b.isCurrent) - Number(a.isCurrent)));
    } catch {
      this.sessionsError.set('No se pudieron cargar las sesiones. Inténtalo de nuevo.');
    } finally {
      this.loadingSessions.set(false);
    }
  }

  async revoke(row: SessionRow): Promise<void> {
    this.busyId.set(row.session.id);
    try {
      await this.clerk.revokeSession(row.session);
      await this.loadSessions();
    } catch {
      this.sessionsError.set('No se pudo cerrar esa sesión.');
    } finally {
      this.busyId.set(null);
    }
  }
}

export function toRow(session: ClerkSession, currentId: string | null): SessionRow {
  const activity = session.latestActivity;
  const browser = [activity?.browserName, activity?.browserVersion?.split('.')[0]].filter(Boolean).join(' ');
  const device = [browser, activity?.deviceType].filter(Boolean).join(' · ') || 'Dispositivo desconocido';
  const place = [activity?.city, activity?.country].filter(Boolean).join(', ');
  const location = [place, activity?.ipAddress].filter(Boolean).join(' · ') || 'Ubicación desconocida';
  return {
    session,
    device,
    location,
    isMobile: !!activity?.isMobile,
    isCurrent: session.id === currentId,
    lastActiveAt: session.lastActiveAt ? new Date(session.lastActiveAt) : null,
  };
}
