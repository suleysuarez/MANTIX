import { CurrencyPipe, DatePipe } from '@angular/common';
import {
  ChangeDetectionStrategy,
  Component,
  HostListener,
  computed,
  input,
  output,
  signal,
} from '@angular/core';

import { initials } from '../../core/equipment-status';
import { Technician, TechnicianUpdatePayload, TechnicianWorkload } from '../../core/technicians.service';
import {
  MAX_SPECIALIZATION,
  STATUS_STYLES,
  Loads,
  specialties,
  technicianStatus,
  validateTechnicianInput,
} from './technician-ui';

const FIELD =
  'w-full rounded-lg border border-[#CED4DA] bg-[#F7FAFC] px-3 py-2 text-[13px] text-[#1E293B] focus:border-[#457b9d] focus:outline-none';

export interface TechnicianEdit {
  payload: TechnicianUpdatePayload;
  notice: string;
}

/**
 * Panel lateral con la ficha de un técnico: carga, especialidades, datos de contacto, historial
 * y, con `technicians.manage`, disponibilidad y edición del perfil. Es presentacional: las
 * acciones se emiten y las ejecuta la pantalla.
 */
@Component({
  selector: 'app-technician-drawer',
  standalone: true,
  imports: [CurrencyPipe, DatePipe],
  template: `
    <div class="fixed inset-0 z-[60] flex justify-end">
      <div class="absolute inset-0 bg-[#0b1f3a]/45" (click)="closed.emit()" aria-hidden="true"></div>
      <section role="dialog" aria-modal="true" [attr.aria-label]="'Ficha de ' + technician().full_name"
        class="relative flex h-full w-full max-w-xl flex-col overflow-hidden bg-white shadow-2xl">
        <header class="flex shrink-0 items-center justify-between gap-3 bg-[#0b1f3a] px-6 py-4">
          <div class="flex items-center gap-2">
            @if (technician().employee_code) {
              <span class="rounded border border-[#ADD7F6]/30 bg-white/10 px-2 py-0.5 font-mono text-[12px] font-bold text-[#ADD7F6]">{{ technician().employee_code }}</span>
            }
            <span class="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[12px] font-bold" [class]="style().chip">
              <span class="h-1.5 w-1.5 rounded-full" [class]="style().dot"></span>{{ style().label }}
            </span>
          </div>
          <button type="button" (click)="closed.emit()" aria-label="Cerrar ficha"
            class="flex h-9 w-9 items-center justify-center rounded-lg !text-[#CED4DA] transition-colors hover:bg-white/15 hover:!text-white">
            <span class="material-symbols-outlined">close</span>
          </button>
        </header>

        <div class="flex-1 space-y-5 overflow-y-auto px-6 py-5">
          @if (error() || copyError()) {
            <p class="rounded-lg bg-[#FEE2E2] px-3 py-2 text-[13px] text-[#991B1B]" role="alert">{{ error() || copyError() }}</p>
          }
          @if (!error() && !copyError() && (notice() || copied())) {
            <p class="flex items-center gap-2 rounded-lg bg-[#D1FAE5] px-3 py-2 text-[13px] font-medium text-[#065F46]" role="status">
              <span class="material-symbols-outlined text-[18px]">check_circle</span>{{ copied() || notice() }}
            </p>
          }

          <div class="flex items-center gap-4">
            <span class="flex h-20 w-20 shrink-0 items-center justify-center rounded-2xl bg-[linear-gradient(135deg,#ADD7F6,#A2D2FF)] text-[26px] font-bold text-[#3E5C76]">{{ initialsOf(technician().full_name) }}</span>
            <div class="min-w-0">
              <h2 class="truncate text-[22px] font-bold text-[#0b1f3a]">{{ technician().full_name }}</h2>
              <p class="text-[13px] text-[#64748B]">{{ technician().specialization || 'Sin especialización registrada' }}</p>
              <p class="truncate text-[12px] text-[#94A3B8]">{{ technician().email }}</p>
            </div>
          </div>

          <dl class="grid grid-cols-3 gap-2 rounded-xl bg-[#EEF4FA] p-4 text-center">
            <div>
              <dd class="text-[20px] font-bold text-[#0b1f3a]">{{ hasWorkload() ? (load()?.open_tickets ?? 0) : '—' }}</dd>
              <dt class="text-[11px] font-bold uppercase text-[#64748B]">Tickets abiertos</dt>
            </div>
            <div class="border-x border-[#CED4DA]/60">
              <dd class="text-[20px] font-bold text-[#0b1f3a]">{{ hasWorkload() ? (load()?.resolved_in_window ?? 0) : '—' }}</dd>
              <dt class="text-[11px] font-bold uppercase text-[#64748B]">Resueltos ({{ windowDays() }} d)</dt>
            </div>
            <div>
              <dd class="text-[20px] font-bold text-[#0b1f3a]">{{ technician().hourly_rate ? (technician().hourly_rate | currency) : '—' }}</dd>
              <dt class="text-[11px] font-bold uppercase text-[#64748B]">Tarifa por hora</dt>
            </div>
          </dl>
          @if (!hasWorkload()) {
            <p class="-mt-3 text-[11px] text-[#94A3B8]">Las métricas de carga no están disponibles para tu perfil.</p>
          }

          <section>
            <h3 class="mb-2 text-[11px] font-bold uppercase tracking-wider text-[#64748B]">Especialidades</h3>
            <div class="flex flex-wrap gap-2">
              @for (item of tags(); track item) {
                <span class="flex items-center gap-1 rounded-lg bg-[#E9EEF5] px-2.5 py-1 text-[12px] font-semibold text-[#0b1f3a]">
                  <span class="material-symbols-outlined text-[16px] text-[#457b9d]">verified</span>{{ item }}
                </span>
              } @empty {
                <p class="text-[12px] text-[#94A3B8]">Aún no se registraron especialidades.</p>
              }
            </div>
          </section>

          <section class="space-y-2 rounded-xl bg-[#EEF4FA] p-4">
            <h3 class="text-[11px] font-bold uppercase tracking-wider text-[#64748B]">Contacto</h3>
            <div class="flex items-center justify-between gap-2">
              <span class="flex min-w-0 items-center gap-2 text-[13px] text-[#0b1f3a]">
                <span class="material-symbols-outlined text-[#64748B]">alternate_email</span>
                <span class="truncate">{{ technician().email }}</span>
              </span>
              <button type="button" (click)="copyEmail()" class="text-[11px] font-bold uppercase !text-[#457b9d] hover:underline">Copiar</button>
            </div>
          </section>

          @if (canManage()) {
            <section class="space-y-3 rounded-xl border border-[#E2E8F0] p-4">
              <h3 class="text-[11px] font-bold uppercase tracking-wider text-[#64748B]">Disponibilidad</h3>
              @if (technician().is_available && (load()?.open_tickets ?? 0) > 0) {
                <p class="rounded-lg bg-[#FEF3C7] px-3 py-2 text-[12px] text-[#92400E]">
                  Tiene {{ load()?.open_tickets }} {{ load()?.open_tickets === 1 ? 'ticket abierto' : 'tickets abiertos' }}: seguirán asignados a esta persona aunque la marques como no disponible.
                </p>
              }
              <button type="button" (click)="availabilityChange.emit(!technician().is_available)" [disabled]="saving()"
                class="rounded-lg border border-[#CED4DA] bg-white px-3 py-2 text-[12px] font-semibold !text-[#3E5C76] transition-colors hover:bg-[#EEF4FA] disabled:opacity-50">
                {{ technician().is_available ? 'Marcar como no disponible' : 'Marcar como disponible' }}
              </button>
            </section>

            <form class="space-y-3 rounded-xl border border-[#E2E8F0] p-4" (submit)="submitEdit($event)">
              <h3 class="text-[11px] font-bold uppercase tracking-wider text-[#64748B]">Editar perfil</h3>
              <label class="block text-[12px] font-bold">Especialización
                <input name="specialization" [value]="technician().specialization ?? ''" [attr.maxlength]="maxSpecialization" class="mt-1 font-normal" [class]="field" placeholder="Ej: Hardware, Redes (separa con comas)" />
              </label>
              <label class="block text-[12px] font-bold">Tarifa por hora
                <input name="rate" type="number" min="0" max="99999999.99" step="0.01" [value]="technician().hourly_rate ?? ''" class="mt-1 font-mono font-normal" [class]="field" />
              </label>
              @if (formError()) {
                <p class="rounded-lg bg-[#FEE2E2] px-3 py-2 text-[12px] text-[#991B1B]" role="alert">{{ formError() }}</p>
              }
              <button type="submit" [disabled]="saving()"
                class="rounded-lg bg-[#0b1f3a] px-4 py-2 text-[12px] font-bold !text-[#D4A017] hover:bg-[#3E5C76] disabled:opacity-50">
                {{ saving() ? 'Guardando…' : 'Guardar cambios' }}
              </button>
            </form>
          }

          <section>
            <h3 class="mb-3 text-[11px] font-bold uppercase tracking-wider text-[#64748B]">Historial (1 evento)</h3>
            <ol class="relative space-y-4 pl-6 before:absolute before:bottom-2 before:left-[9px] before:top-2 before:w-0.5 before:bg-[#E2E8F0]">
              <li class="relative">
                <span class="absolute -left-6 top-1 h-2.5 w-2.5 rounded-full bg-[#10B981] ring-4 ring-white"></span>
                <p class="text-[13px] font-semibold">Creación del perfil de técnico</p>
                <p class="mt-0.5 font-mono text-[11px] text-[#94A3B8]">{{ technician().created_at | date: 'dd/MM/yyyy HH:mm' }}</p>
              </li>
            </ol>
          </section>
        </div>

        <footer class="flex shrink-0 items-center justify-between border-t border-[#E2E8F0] bg-[#F7FAFC] px-6 py-3">
          <button type="button" (click)="closed.emit()" class="rounded-lg px-4 py-2 text-[13px] font-medium !text-[#475569] transition-colors hover:bg-[#E9EEF5]">Cerrar</button>
          @if (!canManage()) {
            <span class="text-[12px] text-[#94A3B8]">Solo lectura</span>
          }
        </footer>
      </section>
    </div>
  `,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class TechnicianDrawerComponent {
  readonly technician = input.required<Technician>();
  readonly load = input<TechnicianWorkload | undefined>(undefined);
  readonly hasWorkload = input(false);
  readonly windowDays = input(30);
  readonly canManage = input(false);
  readonly saving = input(false);
  readonly error = input('');
  readonly notice = input('');

  readonly closed = output<void>();
  readonly availabilityChange = output<boolean>();
  readonly edited = output<TechnicianEdit>();

  readonly field = FIELD;
  readonly maxSpecialization = MAX_SPECIALIZATION;
  readonly formError = signal('');
  readonly copied = signal('');
  readonly copyError = signal('');
  readonly initialsOf = initials;

  readonly tags = computed(() => specialties(this.technician()));
  readonly style = computed(() => {
    const loads: Loads = this.load() ? { [this.technician().id]: this.load() } : {};
    return STATUS_STYLES[technicianStatus(this.technician(), loads)];
  });

  @HostListener('document:keydown.escape')
  onEscape(): void {
    this.closed.emit();
  }

  submitEdit(event: Event): void {
    event.preventDefault();
    const data = new FormData(event.target as HTMLFormElement);
    const specialization = String(data.get('specialization') ?? '').trim();
    const rate = String(data.get('rate') ?? '').trim();
    const error = validateTechnicianInput({ specialization, rate }, false);
    this.formError.set(error);
    if (error) {
      return;
    }
    this.edited.emit({
      payload: { specialization: specialization || null, hourly_rate: rate ? Number(rate) : null },
      notice: 'Perfil actualizado.',
    });
  }

  async copyEmail(): Promise<void> {
    try {
      await navigator.clipboard.writeText(this.technician().email);
      this.copyError.set('');
      this.copied.set('Correo copiado al portapapeles.');
    } catch {
      this.copied.set('');
      this.copyError.set('No se pudo copiar el correo: selecciónalo y cópialo manualmente.');
    }
  }
}
