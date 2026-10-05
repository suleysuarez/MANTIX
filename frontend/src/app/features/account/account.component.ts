import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';

import { ClerkService } from '../../core/clerk.service';
import { ClerkSession } from '../../core/clerk.types';
import { LocalProfile, LocalProfileService } from '../../core/local-profile.service';

export interface SessionRow {
  session: ClerkSession;
  device: string;
  location: string;
  isMobile: boolean;
  isCurrent: boolean;
  lastActiveAt: Date | null;
}

/** Perfil del usuario y dispositivos donde tiene la sesión abierta. */
@Component({
  selector: 'app-account',
  standalone: true,
  imports: [DatePipe],
  template: `
    <div class="tw-reset flex w-full flex-col gap-4 font-sans text-[#1E293B]">
      <section class="flex items-center gap-4 rounded-[18px] bg-white p-5 shadow-[0_8px_25px_rgba(15,23,42,0.05)]">
        <span class="flex h-14 w-14 shrink-0 items-center justify-center rounded-full bg-[#457b9d] text-[18px] font-bold text-white">{{ initials() }}</span>
        <div class="min-w-0">
          <h1 class="truncate text-[20px] font-bold">{{ profile()?.full_name }}</h1>
          <p class="truncate text-[13px] text-[#64748B]">{{ profile()?.email }}</p>
          <div class="mt-1 flex flex-wrap gap-2">
            @for (role of profile()?.roles ?? []; track role.code) {
              <span class="rounded-full bg-[#DBEAFE] px-2.5 py-0.5 text-[11px] font-bold text-[#1D4ED8]">{{ role.name }}</span>
            }
            @if (profile()?.employee_code) {
              <span class="rounded-full bg-[#F1F5F9] px-2.5 py-0.5 text-[11px] font-semibold text-[#64748B]">Código {{ profile()?.employee_code }}</span>
            }
          </div>
        </div>
      </section>

      <section class="rounded-[18px] bg-white p-5 shadow-[0_8px_25px_rgba(15,23,42,0.05)]">
        <div class="mb-3 flex items-center justify-between gap-3">
          <div>
            <h2 class="text-[16px] font-bold">Sesiones activas</h2>
            <p class="text-[12px] text-[#64748B]">Dispositivos donde tu cuenta tiene la sesión abierta. Cierra las que no reconozcas.</p>
          </div>
          <button type="button" (click)="load()" class="flex h-9 items-center gap-1 rounded-full bg-[#F1F5F9] px-4 text-[12px] font-medium hover:bg-[#E2E8F0]">
            <span class="material-symbols-outlined text-[16px]">refresh</span> Actualizar
          </button>
        </div>

        @if (error()) {
          <p class="rounded-xl bg-[#FEF2F2] p-3 text-[13px] text-[#B91C1C]">{{ error() }}</p>
        }
        @if (loading()) {
          <p class="py-6 text-center text-[13px] text-[#64748B]">Cargando sesiones…</p>
        } @else if (rows().length === 0 && !error()) {
          <p class="py-6 text-center text-[13px] text-[#64748B]">No se encontraron sesiones activas.</p>
        }

        <ul class="flex flex-col gap-2">
          @for (row of rows(); track row.session.id) {
            <li class="flex items-center gap-4 rounded-[14px] bg-[#F8FAFC] p-3">
              <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-[#DBEAFE] text-[#2563EB]">
                <span class="material-symbols-outlined text-[22px]">{{ row.isMobile ? 'smartphone' : 'computer' }}</span>
              </span>
              <div class="min-w-0 flex-1">
                <p class="flex items-center gap-2 truncate text-[13px] font-semibold">
                  {{ row.device }}
                  @if (row.isCurrent) {
                    <span class="rounded-full bg-[#D1FAE5] px-2 py-0.5 text-[10px] font-bold text-[#047857]">ESTA SESIÓN</span>
                  }
                </p>
                <p class="truncate text-[12px] text-[#64748B]">
                  {{ row.location }}
                  @if (row.lastActiveAt) {
                    · Última actividad {{ row.lastActiveAt | date: 'd MMM y, HH:mm' }}
                  }
                </p>
              </div>
              @if (!row.isCurrent) {
                <button type="button" (click)="revoke(row)" [disabled]="busyId() === row.session.id"
                  class="h-9 shrink-0 rounded-full border border-[#FECACA] px-4 text-[12px] font-medium text-[#B91C1C] hover:bg-[#FEF2F2] disabled:opacity-50">
                  {{ busyId() === row.session.id ? 'Cerrando…' : 'Cerrar sesión' }}
                </button>
              }
            </li>
          }
        </ul>
      </section>
    </div>
  `,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class AccountComponent implements OnInit {
  private readonly clerk = inject(ClerkService);
  private readonly profileService = inject(LocalProfileService);

  readonly profile = signal<LocalProfile | null>(null);
  readonly rows = signal<SessionRow[]>([]);
  readonly loading = signal(true);
  readonly error = signal('');
  readonly busyId = signal<string | null>(null);
  readonly initials = signal('');

  async ngOnInit(): Promise<void> {
    const profile = await this.profileService.getProfile();
    this.profile.set(profile);
    this.initials.set(
      profile.full_name
        .split(' ')
        .filter(Boolean)
        .slice(0, 2)
        .map((part) => part[0].toUpperCase())
        .join(''),
    );
    await this.load();
  }

  async load(): Promise<void> {
    this.loading.set(true);
    this.error.set('');
    try {
      const { sessions, currentId } = await this.clerk.getActiveSessions();
      this.rows.set(
        sessions
          .map((session) => toRow(session, currentId))
          .sort((a, b) => Number(b.isCurrent) - Number(a.isCurrent)),
      );
    } catch {
      this.error.set('No se pudieron cargar las sesiones. Inténtalo de nuevo.');
    } finally {
      this.loading.set(false);
    }
  }

  async revoke(row: SessionRow): Promise<void> {
    this.busyId.set(row.session.id);
    try {
      await this.clerk.revokeSession(row.session);
      await this.load();
    } catch {
      this.error.set('No se pudo cerrar esa sesión.');
    } finally {
      this.busyId.set(null);
    }
  }
}

function toRow(session: ClerkSession, currentId: string | null): SessionRow {
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
