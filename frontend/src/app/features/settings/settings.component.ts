import { AsyncPipe, DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';

import { LocalProfileService } from '../../core/local-profile.service';
import { HealthStatus } from '../../core/settings.service';
import { SettingsStore } from '../../core/settings.store';
import { ToastHostComponent } from '../../shared/toast-host.component';
import { CategoriesSectionComponent } from './categories-section.component';
import { PrioritiesSectionComponent } from './priorities-section.component';

type Section = 'health' | 'categories' | 'priorities' | 'environment';

const SECTIONS: { id: Section; label: string; icon: string }[] = [
  { id: 'health', label: 'Salud del sistema', icon: 'monitor_heart' },
  { id: 'categories', label: 'Categorías', icon: 'category' },
  { id: 'priorities', label: 'Prioridades y SLA', icon: 'flag' },
  { id: 'environment', label: 'Parámetros', icon: 'tune' },
];
const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';
/** Estado con texto y símbolo, nunca solo color. */
const STATUS: Record<HealthStatus | 'never', { label: string; symbol: string; tone: string }> = {
  ok: { label: 'Operativo', symbol: '✓', tone: 'bg-brand-accentLight/60 text-brand-accentDeep' },
  warning: { label: 'Atención', symbol: '!', tone: 'bg-secondary-fixed text-on-secondary-fixed' },
  error: { label: 'Con fallo', symbol: '✕', tone: 'bg-error-container text-on-error-container' },
  disabled: { label: 'Desactivado', symbol: '–', tone: 'bg-surface-container-high text-on-surface-variant' },
  never: { label: 'Sin ejecutar', symbol: '–', tone: 'bg-surface-container-high text-on-surface-variant' },
};

/** Configuración: navegación vertical por secciones; salud del sistema, catálogos y parámetros. */
@Component({
  selector: 'app-settings',
  standalone: true,
  imports: [AsyncPipe, DatePipe, CategoriesSectionComponent, PrioritiesSectionComponent, ToastHostComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (vm$ | async; as vm) {
      <div class="grid gap-4 md:grid-cols-[14rem_minmax(0,1fr)]">
        <nav class="glass h-fit rounded-2xl p-2 md:sticky md:top-4" aria-label="Secciones de configuración">
          <ul class="flex gap-1 overflow-x-auto md:flex-col">
            @for (s of sections; track s.id) {
              <li>
                <button type="button" (click)="section.set(s.id)" [attr.aria-current]="section() === s.id ? 'page' : null"
                  [class]="focus + ' flex w-full items-center gap-2 whitespace-nowrap rounded-xl px-3 py-2 text-left text-[13px] font-semibold ' + (section() === s.id ? 'bg-brand-sidebar !text-white' : 'bg-transparent !text-brand-accentDeep hover:bg-surface-container-high')">
                  <span class="material-symbols-outlined text-[18px]" aria-hidden="true">{{ s.icon }}</span>{{ s.label }}
                </button>
              </li>
            }
          </ul>
        </nav>

        <div class="min-w-0">
          @switch (section()) {
            @case ('health') {
              <section aria-labelledby="health-title" class="space-y-4" [attr.aria-busy]="vm.healthLoading">
                <header class="flex flex-wrap items-start justify-between gap-2">
                  <div>
                    <h2 id="health-title" class="text-[18px] font-bold text-on-surface">Salud del sistema</h2>
                    @if (vm.health; as h) { <p class="text-[12px] text-on-surface-variant">Revisado el {{ h.generated_at | date: 'dd/MM/yyyy HH:mm:ss' }}</p> }
                  </div>
                  <button type="button" (click)="reload()" [disabled]="vm.healthLoading" [class]="focus + ' glass-btn rounded-lg px-4 py-2 text-[13px] font-bold disabled:opacity-50'">{{ vm.healthLoading ? 'Revisando…' : 'Volver a revisar' }}</button>
                </header>
                @if (vm.healthError) { <p role="alert" class="rounded-lg bg-error-container px-3 py-2 text-[13px] text-on-error-container">{{ vm.healthError }}</p> }
                @if (vm.health; as h) {
                  <p [class]="'inline-flex items-center gap-2 rounded-full px-3 py-1 text-[13px] font-bold ' + tone(h.overall)">
                    <span aria-hidden="true">{{ status(h.overall).symbol }}</span> Estado general: {{ status(h.overall).label }}
                  </p>

                  <dl class="grid grid-cols-2 gap-3 md:grid-cols-4" aria-label="Usuarios">
                    <div class="glass rounded-xl p-3"><dt class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Usuarios</dt><dd class="text-[22px] font-bold text-on-surface">{{ h.users.total }}</dd></div>
                    <div class="glass rounded-xl p-3"><dt class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Activos</dt><dd class="text-[22px] font-bold text-on-surface">{{ h.users.active }}</dd></div>
                    <div class="glass rounded-xl p-3"><dt class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Inactivos</dt><dd class="text-[22px] font-bold text-on-surface">{{ h.users.inactive }}</dd></div>
                    <div class="glass rounded-xl p-3"><dt class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Sin rol</dt><dd class="text-[22px] font-bold text-on-surface">{{ h.users.without_role }}</dd>
                      @if (h.users.without_role > 0) { <p class="text-[11px] text-on-surface-variant">Esperan aprobación</p> }</div>
                  </dl>

                  <section aria-labelledby="int-title" class="rounded-2xl border border-brand-grey bg-surface-container-lowest p-4">
                    <h3 id="int-title" class="text-[13px] font-bold uppercase tracking-wider text-brand-accentDeep">Integraciones</h3>
                    <ul class="mt-2 divide-y divide-brand-grey/60">
                      @for (i of h.integrations; track i.key) {
                        <li class="flex flex-wrap items-center gap-3 py-2">
                          <span class="min-w-0 flex-1"><span class="block text-[13px] font-semibold text-on-surface">{{ i.name }}</span><span class="block text-[12px] text-on-surface-variant">{{ i.detail }}@if (i.latency_ms !== null) { · {{ i.latency_ms }} ms }</span></span>
                          <span [class]="'rounded-full px-2.5 py-0.5 text-[11px] font-bold ' + tone(i.status)"><span aria-hidden="true">{{ status(i.status).symbol }}</span> {{ status(i.status).label }}</span>
                        </li>
                      }
                    </ul>
                  </section>

                  <section aria-labelledby="job-title" class="rounded-2xl border border-brand-grey bg-surface-container-lowest p-4">
                    <h3 id="job-title" class="text-[13px] font-bold uppercase tracking-wider text-brand-accentDeep">Tareas programadas</h3>
                    <ul class="mt-2 divide-y divide-brand-grey/60">
                      @for (j of h.jobs; track j.id) {
                        <li class="flex flex-wrap items-center gap-3 py-2">
                          <span class="min-w-0 flex-1">
                            <span class="block text-[13px] font-semibold text-on-surface">{{ j.name }}</span>
                            <span class="block text-[12px] text-on-surface-variant">
                              @if (j.running) { Cada {{ j.interval_minutes }} min · próxima {{ j.next_run_at | date: 'dd/MM HH:mm' }} } @else { Programador detenido }
                              · última: {{ j.last_run_at ? (j.last_run_at | date: 'dd/MM HH:mm') : 'aún no se ha ejecutado desde el arranque' }}@if (j.last_detail) { ({{ j.last_detail }}) }
                            </span>
                          </span>
                          <span [class]="'rounded-full px-2.5 py-0.5 text-[11px] font-bold ' + tone(j.running ? j.last_status : 'disabled')"><span aria-hidden="true">{{ status(j.running ? j.last_status : 'disabled').symbol }}</span> {{ status(j.running ? j.last_status : 'disabled').label }}</span>
                        </li>
                      }
                    </ul>
                  </section>

                  <div class="grid gap-4 lg:grid-cols-2">
                    <section aria-labelledby="role-title" class="rounded-2xl border border-brand-grey bg-surface-container-lowest p-4">
                      <h3 id="role-title" class="text-[13px] font-bold uppercase tracking-wider text-brand-accentDeep">Roles</h3>
                      <table class="mt-2 w-full text-left text-[12px]">
                        <caption class="sr-only">Usuarios activos y permisos por rol</caption>
                        <thead><tr class="text-[11px] uppercase tracking-wider text-on-surface-variant"><th scope="col" class="py-1 font-bold">Rol</th><th scope="col" class="py-1 text-right font-bold">Usuarios</th><th scope="col" class="py-1 text-right font-bold">Permisos</th></tr></thead>
                        <tbody>
                          @for (r of h.roles; track r.id) {
                            <tr class="border-t border-brand-grey/60"><td class="py-1.5 text-on-surface">{{ r.name }}@if (!r.is_active) { <span class="ml-1 text-on-surface-variant">(inactivo)</span> }</td><td class="py-1.5 text-right text-on-surface">{{ r.users }}</td><td class="py-1.5 text-right text-on-surface">{{ r.permissions }}</td></tr>
                          }
                        </tbody>
                      </table>
                    </section>
                    <section aria-labelledby="aud-title" class="rounded-2xl border border-brand-grey bg-surface-container-lowest p-4">
                      <h3 id="aud-title" class="text-[13px] font-bold uppercase tracking-wider text-brand-accentDeep">Auditoría · {{ h.audit.last_24h }} en 24 h</h3>
                      @if (h.audit.recent.length > 0) {
                        <ul class="mt-2 space-y-1.5">
                          @for (a of h.audit.recent; track a.id) {
                            <li class="text-[12px] text-on-surface"><span class="font-mono">{{ a.action }}</span> <span class="text-on-surface-variant">· {{ a.by ?? 'sistema' }} · {{ a.at | date: 'dd/MM HH:mm' }}</span></li>
                          }
                        </ul>
                      } @else { <p class="mt-2 text-[12px] text-on-surface-variant">Sin acciones registradas.</p> }
                    </section>
                  </div>
                } @else if (vm.healthLoading) {
                  <div class="space-y-3" role="status" aria-label="Revisando el sistema">
                    @for (n of skeleton; track n) { <div class="h-20 animate-pulse rounded-2xl bg-surface-container motion-reduce:animate-none"></div> }
                  </div>
                }
              </section>
            }
            @case ('categories') {
              <app-categories-section [categories]="vm.categories" [loading]="vm.categoriesLoading" [error$]="vm.categoriesError"
                [saving]="vm.saving" [canManage]="canManage()" [serverErrors]="vm.fieldErrors" />
            }
            @case ('priorities') {
              <app-priorities-section [priorities]="vm.priorities" [loading]="vm.prioritiesLoading" [error]="vm.prioritiesError"
                [saving]="vm.saving" [canManage]="canManage()" [serverErrors]="vm.fieldErrors" />
            }
            @case ('environment') {
              <section aria-labelledby="env-title" class="space-y-3">
                <header>
                  <h2 id="env-title" class="text-[18px] font-bold text-on-surface">Parámetros del sistema</h2>
                  <p class="text-[13px] text-on-surface-variant">Solo lectura. Se cambian con variables de entorno en el servidor y requieren reiniciarlo; aquí nunca se muestran secretos.</p>
                </header>
                @if (vm.health; as h) {
                  <dl class="divide-y divide-brand-grey/60 rounded-2xl border border-brand-grey bg-surface-container-lowest">
                    @for (p of parameters(h.environment); track p.label) {
                      <div class="flex flex-wrap justify-between gap-2 px-4 py-2.5"><dt class="text-[13px] text-on-surface-variant">{{ p.label }}</dt><dd class="text-[13px] font-semibold text-on-surface">{{ p.value }}</dd></div>
                    }
                  </dl>
                } @else {
                  <p class="text-[13px] text-on-surface-variant">{{ vm.healthLoading ? 'Cargando…' : 'No se pudieron leer los parámetros.' }}</p>
                }
              </section>
            }
          }
        </div>
      </div>
      <app-toast-host />
    }
  `,
})
export class SettingsComponent implements OnInit {
  readonly store = inject(SettingsStore);
  private readonly profile = inject(LocalProfileService);

  readonly vm$ = this.store.state$;
  readonly sections = SECTIONS;
  readonly focus = FOCUS;
  readonly skeleton = [1, 2, 3];
  readonly section = signal<Section>('health');
  /** Escribir catálogos exige `priorities.manage`; sin él se ve pero no se edita. */
  readonly canManage = signal(false);

  ngOnInit(): void {
    this.store.loadAll();
    void this.profile.can('priorities.manage').then((allowed) => this.canManage.set(allowed)).catch(() => this.canManage.set(false));
  }

  reload(): void {
    this.store.loadHealth();
  }

  status(key: HealthStatus | 'never' | 'ok' | 'warning' | 'error') {
    return STATUS[key];
  }

  tone(key: HealthStatus | 'never'): string {
    return STATUS[key].tone;
  }

  parameters(env: { name: string; version: string; rate_limit_per_minute: number; max_upload_mb: number; reminder_interval_minutes: number; log_level: string; scheduler_enabled: boolean }): { label: string; value: string }[] {
    return [
      { label: 'Entorno', value: env.name },
      { label: 'Versión de la API', value: env.version },
      { label: 'Límite de peticiones', value: `${env.rate_limit_per_minute} por minuto` },
      { label: 'Tamaño máximo de adjunto', value: `${env.max_upload_mb} MB` },
      { label: 'Recordatorios preventivos', value: env.scheduler_enabled ? `cada ${env.reminder_interval_minutes} min` : 'programador desactivado' },
      { label: 'Nivel de registro', value: env.log_level },
    ];
  }
}
