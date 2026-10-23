import { AsyncPipe, DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, HostListener, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';

import { PermissionsService } from '../../core/permissions.service';
import { SettingsState, SettingsStore } from '../../core/settings.store';
import { ToastHostComponent } from '../../shared/toast-host.component';
import { CategoriesSectionComponent } from './categories-section.component';
import { OrganizationSectionComponent } from './organization-section.component';
import { PrioritiesSectionComponent } from './priorities-section.component';
import { STATUS, ShownStatus, actionLabel, attentionTone, frequencyText, integrationLabel, jobName, jobStatus, jobStatusLabel } from './settings-ui';

type Modal = 'organization' | 'catalogs' | 'integrations' | null;
type CatalogTab = 'categories' | 'priorities';

const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';
const CARD = 'glass flex flex-col rounded-2xl p-5';
const CARD_BUTTON = `flex w-full items-center justify-center gap-2 rounded-xl border border-brand-grey bg-transparent px-4 py-2.5 text-[13px] font-semibold !text-brand-accentDeep transition-colors hover:bg-surface-container-high ${FOCUS}`;

/**
 * Configuración en una sola pantalla: parámetros generales, resumen de usuarios y roles,
 * integraciones, catálogos de mantenimiento, salud del sistema, tareas programadas, roles y
 * últimos registros de auditoría. Lo editable (organización y catálogos) se abre en una ventana.
 */
@Component({
  selector: 'app-settings',
  standalone: true,
  imports: [AsyncPipe, DatePipe, RouterLink, CategoriesSectionComponent, OrganizationSectionComponent, PrioritiesSectionComponent, ToastHostComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (vm$ | async; as vm) {
      <div class="space-y-4">
        <header class="flex flex-wrap items-end justify-between gap-2">
          <div>
            <h1 class="text-[22px] font-extrabold text-on-surface">Configuración</h1>
            <p class="text-[13px] text-on-surface-variant">Parámetros, catálogos y estado del sistema.
              @if (vm.health; as h) { Revisado el {{ h.generated_at | date: 'dd/MM/yyyy HH:mm' }}. }</p>
          </div>
          <button type="button" (click)="store.loadHealth()" [disabled]="vm.healthLoading" [class]="focus + ' flex items-center gap-1.5 rounded-xl border border-brand-grey bg-transparent px-4 py-2 text-[13px] font-semibold !text-brand-accentDeep hover:bg-surface-container-high disabled:opacity-50'">
            <span class="material-symbols-outlined text-[18px]" aria-hidden="true">refresh</span>{{ vm.healthLoading ? 'Revisando…' : 'Volver a revisar' }}
          </button>
        </header>

        @if (vm.healthError) {
          <p role="alert" class="rounded-lg bg-error-container px-4 py-3 text-[13px] text-on-error-container">{{ vm.healthError }}</p>
        }

        <!-- Fila 1 -->
        <div class="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
          <!-- Configuración general -->
          <section [class]="card" aria-labelledby="cfg-general">
            <div class="flex items-center gap-3">
              <span [class]="badge" aria-hidden="true"><span class="material-symbols-outlined text-[26px]">settings</span></span>
              <div class="min-w-0">
                <h2 id="cfg-general" class="text-[16px] font-bold text-on-surface">Configuración general</h2>
                <p class="text-[12px] text-on-surface-variant">Parámetros básicos del sistema.</p>
              </div>
            </div>
            <dl class="mt-4 flex-1 divide-y divide-brand-grey/40 text-[13px]">
              <div class="flex items-center justify-between gap-3 py-2.5"><dt class="flex items-center gap-2 text-on-surface-variant"><span class="material-symbols-outlined text-[18px]" aria-hidden="true">apartment</span>Organización</dt><dd class="m-0 truncate text-right font-bold text-on-surface">{{ vm.organization?.company_name ?? '—' }}</dd></div>
              <div class="flex items-center justify-between gap-3 py-2.5"><dt class="flex items-center gap-2 text-on-surface-variant"><span class="material-symbols-outlined text-[18px]" aria-hidden="true">schedule</span>Zona horaria</dt><dd class="m-0 text-right font-bold text-on-surface">América/Bogotá (UTC-5)</dd></div>
              <div class="flex items-center justify-between gap-3 py-2.5"><dt class="flex items-center gap-2 text-on-surface-variant"><span class="material-symbols-outlined text-[18px]" aria-hidden="true">language</span>Idioma</dt><dd class="m-0 text-right font-bold text-on-surface">Español</dd></div>
              <div class="flex items-center justify-between gap-3 py-2.5"><dt class="flex items-center gap-2 text-on-surface-variant"><span class="material-symbols-outlined text-[18px]" aria-hidden="true">calendar_month</span>Formato de fecha</dt><dd class="m-0 text-right font-bold text-on-surface">DD/MM/AAAA</dd></div>
            </dl>
            <button type="button" [class]="cardButton + ' mt-3'" (click)="modal.set('organization')">
              <span class="material-symbols-outlined text-[18px]" aria-hidden="true">{{ canManage() ? 'edit' : 'visibility' }}</span>{{ canManage() ? 'Editar organización' : 'Ver organización' }}
            </button>
          </section>

          <!-- Usuarios y roles -->
          <section [class]="card" aria-labelledby="cfg-users">
            <div class="flex items-center gap-3">
              <span [class]="badge" aria-hidden="true"><span class="material-symbols-outlined text-[26px]">groups</span></span>
              <div class="min-w-0">
                <h2 id="cfg-users" class="text-[16px] font-bold text-on-surface">Usuarios y roles</h2>
                <p class="text-[12px] text-on-surface-variant">Cuentas y permisos.</p>
              </div>
            </div>
            @if (vm.health; as h) {
              <dl class="mt-4 flex-1 divide-y divide-brand-grey/40 text-[13px]">
                <div class="flex items-center justify-between py-2.5"><dt class="text-on-surface-variant">Total de usuarios</dt><dd class="m-0 font-bold text-on-surface">{{ h.users.total }}</dd></div>
                <div class="flex items-center justify-between py-2.5"><dt class="text-on-surface-variant">Roles definidos</dt><dd class="m-0 font-bold text-on-surface">{{ h.roles.length }}</dd></div>
                <div class="flex items-center justify-between py-2.5"><dt class="text-on-surface-variant">Usuarios activos</dt><dd class="m-0 font-bold text-on-surface">{{ h.users.active }}</dd></div>
                <div class="flex items-center justify-between py-2.5"><dt class="text-on-surface-variant">Usuarios inactivos</dt><dd class="m-0 font-bold text-on-surface">{{ h.users.inactive }}</dd></div>
              </dl>
            } @else {
              <div class="mt-4 h-32 flex-1 animate-pulse rounded-lg bg-surface-container motion-reduce:animate-none" role="status" aria-label="Cargando usuarios"></div>
            }
            <a routerLink="/usuarios" [class]="cardButton + ' mt-3'">
              <span class="material-symbols-outlined text-[18px]" aria-hidden="true">manage_accounts</span>Gestionar usuarios
            </a>
          </section>

          <!-- Integraciones -->
          <section [class]="card" aria-labelledby="cfg-int">
            <div class="flex items-center gap-3">
              <span [class]="badge" aria-hidden="true"><span class="material-symbols-outlined text-[26px]">link</span></span>
              <div class="min-w-0">
                <h2 id="cfg-int" class="text-[16px] font-bold text-on-surface">Integraciones</h2>
                <p class="text-[12px] text-on-surface-variant">Conexiones con servicios externos.</p>
              </div>
            </div>
            @if (vm.health; as h) {
              <ul class="mt-4 flex-1 divide-y divide-brand-grey/40">
                @for (i of h.integrations; track i.key) {
                  <li class="flex items-center justify-between gap-3 py-2.5">
                    <span class="min-w-0 truncate text-[13px] font-semibold text-on-surface">{{ i.name }}</span>
                    <span [class]="'inline-flex shrink-0 items-center gap-1.5 rounded-full px-2.5 py-1 text-[11px] font-bold ' + status(i.status).tone"><span class="h-1.5 w-1.5 rounded-full" [class]="status(i.status).dot"></span>{{ integrationText(i.status) }}</span>
                  </li>
                }
              </ul>
            } @else {
              <div class="mt-4 h-32 flex-1 animate-pulse rounded-lg bg-surface-container motion-reduce:animate-none" role="status" aria-label="Cargando integraciones"></div>
            }
            <button type="button" [class]="cardButton + ' mt-3'" (click)="modal.set('integrations')" [disabled]="!vm.health">
              <span class="material-symbols-outlined text-[18px]" aria-hidden="true">link</span>Ver detalles
            </button>
          </section>

          <!-- Mantenimiento -->
          <section [class]="card" aria-labelledby="cfg-maint">
            <div class="flex items-center gap-3">
              <span [class]="badge" aria-hidden="true"><span class="material-symbols-outlined text-[26px]">build</span></span>
              <div class="min-w-0">
                <h2 id="cfg-maint" class="text-[16px] font-bold text-on-surface">Mantenimiento</h2>
                <p class="text-[12px] text-on-surface-variant">Catálogos y reglas operativas.</p>
              </div>
            </div>
            <dl class="mt-4 flex-1 divide-y divide-brand-grey/40 text-[13px]">
              <div class="flex items-center justify-between py-2.5"><dt class="flex items-center gap-2 text-on-surface-variant"><span class="material-symbols-outlined text-[18px]" aria-hidden="true">category</span>Categorías activas</dt><dd class="m-0 font-bold text-on-surface">{{ activeCount(vm.categories) }}</dd></div>
              <div class="flex items-center justify-between py-2.5"><dt class="flex items-center gap-2 text-on-surface-variant"><span class="material-symbols-outlined text-[18px]" aria-hidden="true">flag</span>Prioridades activas</dt><dd class="m-0 font-bold text-on-surface">{{ activeCount(vm.priorities) }}</dd></div>
              <div class="flex items-center justify-between py-2.5"><dt class="flex items-center gap-2 text-on-surface-variant"><span class="material-symbols-outlined text-[18px]" aria-hidden="true">notifications_active</span>Avisos preventivos</dt><dd class="m-0 font-bold text-on-surface">{{ reminders(vm) }}</dd></div>
              <div class="flex items-center justify-between py-2.5"><dt class="flex items-center gap-2 text-on-surface-variant"><span class="material-symbols-outlined text-[18px]" aria-hidden="true">attach_file</span>Adjunto máximo</dt><dd class="m-0 font-bold text-on-surface">{{ vm.health ? vm.health.environment.max_upload_mb + ' MB' : '—' }}</dd></div>
            </dl>
            <button type="button" [class]="cardButton + ' mt-3'" (click)="modal.set('catalogs')">
              <span class="material-symbols-outlined text-[18px]" aria-hidden="true">tune</span>{{ canManage() ? 'Gestionar catálogos' : 'Ver catálogos' }}
            </button>
          </section>
        </div>

        <!-- Fila 2 -->
        <div class="grid grid-cols-1 gap-4 xl:grid-cols-12">
          <!-- Salud del sistema -->
          <section [class]="card + ' xl:col-span-4'" aria-labelledby="cfg-health" [attr.aria-busy]="vm.healthLoading">
            <div class="flex items-center gap-3">
              <span [class]="badge" aria-hidden="true"><span class="material-symbols-outlined text-[26px]">monitor_heart</span></span>
              <div class="min-w-0 flex-1">
                <h2 id="cfg-health" class="text-[16px] font-bold text-on-surface">Salud del sistema</h2>
                <p class="text-[12px] text-on-surface-variant">Estado general de los componentes.</p>
              </div>
              @if (vm.health; as h) {
                <span [class]="'inline-flex shrink-0 items-center gap-1.5 rounded-full px-2.5 py-1 text-[12px] font-bold ' + status(h.overall).tone"><span class="h-1.5 w-1.5 rounded-full" [class]="status(h.overall).dot"></span>{{ status(h.overall).label }}</span>
              }
            </div>
            @if (vm.health; as h) {
              <dl class="mt-4 grid grid-cols-2 gap-3">
                <div class="rounded-xl bg-[#EEF4FA] p-3"><dt class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Usuarios</dt><dd class="m-0 text-[24px] font-extrabold text-on-surface">{{ h.users.total }}</dd><p class="text-[11px] text-on-surface-variant">{{ h.users.active }} activos · {{ h.users.inactive }} inactivos</p></div>
                <div class="rounded-xl bg-[#EEF4FA] p-3"><dt class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Auditoría</dt><dd class="m-0 text-[24px] font-extrabold text-on-surface">{{ h.audit.last_24h }}</dd><p class="text-[11px] text-on-surface-variant">acciones en 24 h</p></div>
                <div class="rounded-xl bg-[#EEF4FA] p-3"><dt class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Tareas</dt><dd class="m-0 text-[24px] font-extrabold text-on-surface">{{ jobsFailing(h) }}</dd><p class="text-[11px] text-on-surface-variant">{{ jobsFailing(h) === 1 ? 'con fallo o detenida' : 'con fallo o detenidas' }}</p></div>
                <div [class]="'rounded-xl p-3 ' + attention(h.users.without_role)"><dt class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Sin rol</dt><dd class="m-0 text-[24px] font-extrabold text-on-surface">{{ h.users.without_role }}</dd>
                  @if (h.users.without_role > 0) { <a routerLink="/admin/pending-users" class="text-[11px] font-bold !text-[#92400E] underline {{ focus }}">Esperan autorización</a> } @else { <p class="text-[11px] text-on-surface-variant">Nadie en espera</p> }</div>
              </dl>
              <h3 class="mb-1 mt-4 flex items-center gap-2 text-[13px] font-bold text-on-surface"><span class="material-symbols-outlined text-[18px] text-brand-accentDeep" aria-hidden="true">link</span>Integraciones</h3>
              <ul class="divide-y divide-brand-grey/40">
                @for (i of h.integrations; track i.key) {
                  <li class="flex items-center justify-between gap-2 py-2 text-[12px]">
                    <span class="min-w-0 truncate font-semibold text-on-surface">{{ i.name }}</span>
                    <span class="flex shrink-0 items-center gap-3 text-on-surface-variant">
                      <span class="inline-flex items-center gap-1.5"><span class="h-1.5 w-1.5 rounded-full" [class]="status(i.status).dot"></span>{{ integrationText(i.status) }}</span>
                      <span class="w-14 text-right font-mono">{{ i.latency_ms !== null ? i.latency_ms + ' ms' : '—' }}</span>
                    </span>
                  </li>
                }
              </ul>
            } @else if (vm.healthLoading) {
              <div class="mt-4 h-64 animate-pulse rounded-xl bg-surface-container motion-reduce:animate-none" role="status" aria-label="Revisando el sistema"></div>
            }
          </section>

          <!-- Tareas programadas -->
          <section [class]="card + ' xl:col-span-5'" aria-labelledby="cfg-jobs">
            <div class="flex items-center gap-3">
              <span [class]="badge" aria-hidden="true"><span class="material-symbols-outlined text-[26px]">event_repeat</span></span>
              <div class="min-w-0">
                <h2 id="cfg-jobs" class="text-[16px] font-bold text-on-surface">Tareas programadas</h2>
                <p class="text-[12px] text-on-surface-variant">Procesos automáticos del sistema.</p>
              </div>
            </div>
            @if (vm.health; as h) {
              <div class="mt-4 overflow-x-auto">
                <table class="w-full min-w-[34rem] text-left text-[12px]">
                  <caption class="sr-only">Tareas programadas</caption>
                  <thead>
                    <tr class="bg-surface-container-low text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">
                      <th scope="col" class="rounded-l-lg px-3 py-2">Tarea</th><th scope="col" class="px-3 py-2">Frecuencia</th>
                      <th scope="col" class="px-3 py-2">Última ejecución</th><th scope="col" class="px-3 py-2">Próxima ejecución</th><th scope="col" class="rounded-r-lg px-3 py-2">Estado</th>
                    </tr>
                  </thead>
                  <tbody>
                    @for (j of h.jobs; track j.id) {
                      <tr class="border-b border-brand-grey/40 last:border-0">
                        <td class="px-3 py-2.5 font-semibold text-on-surface">{{ jobLabel(j) }}</td>
                        <td class="px-3 py-2.5 text-on-surface">{{ frequency(j.interval_minutes) }}</td>
                        <td class="px-3 py-2.5 text-on-surface-variant">{{ j.last_run_at ? (j.last_run_at | date: 'dd/MM/yyyy HH:mm') : 'Aún no se ejecuta' }}@if (j.last_detail) { <span class="block text-[11px]">{{ j.last_detail }}</span> }</td>
                        <td class="px-3 py-2.5 text-on-surface-variant">{{ j.running && j.next_run_at ? (j.next_run_at | date: 'dd/MM/yyyy HH:mm') : '—' }}</td>
                        <td class="px-3 py-2.5"><span [class]="'inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[11px] font-bold ' + status(jobState(j)).tone"><span class="h-1.5 w-1.5 rounded-full" [class]="status(jobState(j)).dot"></span>{{ jobStateLabel(j) }}</span></td>
                      </tr>
                    } @empty {
                      <tr><td colspan="5" class="px-3 py-6 text-center text-on-surface-variant">No hay tareas programadas.</td></tr>
                    }
                  </tbody>
                </table>
              </div>
              <p class="mt-3 text-[11px] text-on-surface-variant">{{ h.jobs.length }} {{ h.jobs.length === 1 ? 'tarea programada' : 'tareas programadas' }}. Los horarios de ejecución se reinician al arrancar el servidor.</p>
            } @else if (vm.healthLoading) {
              <div class="mt-4 h-48 animate-pulse rounded-xl bg-surface-container motion-reduce:animate-none" role="status" aria-label="Cargando tareas"></div>
            }
          </section>

          <!-- Roles y permisos -->
          <section [class]="card + ' xl:col-span-3'" aria-labelledby="cfg-roles">
            <div class="flex items-center gap-3">
              <span [class]="badge" aria-hidden="true"><span class="material-symbols-outlined text-[26px]">shield_person</span></span>
              <div class="min-w-0">
                <h2 id="cfg-roles" class="text-[16px] font-bold text-on-surface">Roles y permisos</h2>
                <p class="text-[12px] text-on-surface-variant">Resumen de la configuración.</p>
              </div>
            </div>
            @if (vm.health; as h) {
              <ul class="mt-4 divide-y divide-brand-grey/40">
                @for (r of h.roles; track r.id) {
                  <li class="flex items-center justify-between gap-2 py-2.5">
                    <span class="min-w-0"><span class="block truncate text-[13px] font-bold text-on-surface">{{ r.name }}@if (!r.is_active) { <span class="font-normal text-on-surface-variant"> (inactivo)</span> }</span><span class="block text-[11px] text-on-surface-variant">{{ r.permissions }} {{ r.permissions === 1 ? 'permiso' : 'permisos' }}</span></span>
                    <span class="shrink-0 text-[12px] text-on-surface-variant">{{ r.users }} {{ r.users === 1 ? 'usuario' : 'usuarios' }}</span>
                  </li>
                }
              </ul>
              <div class="mt-3 rounded-xl bg-[#EEF4FA] p-3">
                <h3 class="flex items-center gap-2 text-[12px] font-bold text-on-surface"><span class="material-symbols-outlined text-[16px] text-brand-accentDeep" aria-hidden="true">history</span>Últimos registros de auditoría</h3>
                <ul class="mt-2 space-y-1.5">
                  @for (a of h.audit.recent; track a.id) {
                    <li class="flex items-baseline justify-between gap-2 text-[11px]">
                      <span class="min-w-0 truncate"><strong class="text-on-surface">{{ a.by ?? 'Sistema' }}</strong> <span class="text-on-surface-variant">· {{ action(a.action) }}</span></span>
                      <time class="shrink-0 font-mono text-on-surface-variant" [attr.datetime]="a.at">{{ a.at | date: 'dd/MM HH:mm' }}</time>
                    </li>
                  } @empty {
                    <li class="text-[11px] text-on-surface-variant">Sin acciones registradas.</li>
                  }
                </ul>
              </div>
            } @else if (vm.healthLoading) {
              <div class="mt-4 h-64 animate-pulse rounded-xl bg-surface-container motion-reduce:animate-none" role="status" aria-label="Cargando roles"></div>
            }
          </section>
        </div>
      </div>

      <!-- Ventanas -->
      @if (modal(); as open) {
        <div class="fixed inset-0 z-[55] flex items-end justify-center p-0 sm:items-center sm:p-4">
          <div class="absolute inset-0 bg-brand-navy/50" (click)="modal.set(null)" aria-hidden="true"></div>
          <div class="glass relative max-h-[92vh] w-full overflow-y-auto rounded-t-2xl sm:rounded-2xl" [class]="open === 'catalogs' ? 'max-w-4xl' : 'max-w-xl'" role="dialog" aria-modal="true" [attr.aria-label]="modalTitle(open)">
            <header class="sticky top-0 z-10 flex items-center justify-between gap-3 border-b border-brand-grey/70 bg-surface-container-lowest/90 px-5 py-3 backdrop-blur">
              <h2 class="text-[16px] font-bold text-on-surface">{{ modalTitle(open) }}</h2>
              <button type="button" (click)="modal.set(null)" aria-label="Cerrar" class="rounded-lg bg-transparent p-1 !text-on-surface-variant hover:bg-surface-container {{ focus }}">
                <span class="material-symbols-outlined text-[20px]" aria-hidden="true">close</span>
              </button>
            </header>
            <div class="p-5">
              @switch (open) {
                @case ('organization') {
                  <app-organization-section [organization]="vm.organization" [loading]="vm.organizationLoading" [error]="vm.organizationError"
                    [saving]="vm.saving" [canManage]="canManage()" [serverErrors]="vm.fieldErrors" />
                }
                @case ('catalogs') {
                  <div role="tablist" aria-label="Catálogos" class="mb-4 flex gap-1 border-b border-brand-grey/70">
                    @for (t of catalogTabs; track t.id) {
                      <button type="button" role="tab" [attr.aria-selected]="catalog() === t.id" (click)="catalog.set(t.id)"
                        class="-mb-px border-b-2 bg-transparent px-4 py-2 text-[13px] font-semibold {{ focus }}"
                        [class]="catalog() === t.id ? 'border-brand-accentDeep !text-brand-accentDeep' : 'border-transparent !text-on-surface-variant hover:!text-on-surface'">{{ t.label }}</button>
                    }
                  </div>
                  @if (catalog() === 'categories') {
                    <app-categories-section [categories]="vm.categories" [loading]="vm.categoriesLoading" [error$]="vm.categoriesError"
                      [saving]="vm.saving" [canManage]="canManage()" [serverErrors]="vm.fieldErrors" />
                  } @else {
                    <app-priorities-section [priorities]="vm.priorities" [loading]="vm.prioritiesLoading" [error]="vm.prioritiesError"
                      [saving]="vm.saving" [canManage]="canManage()" [serverErrors]="vm.fieldErrors" />
                  }
                }
                @case ('integrations') {
                  @if (vm.health; as h) {
                    <ul class="divide-y divide-brand-grey/40">
                      @for (i of h.integrations; track i.key) {
                        <li class="flex flex-wrap items-center gap-3 py-3">
                          <span class="min-w-0 flex-1"><span class="block text-[14px] font-bold text-on-surface">{{ i.name }}</span><span class="block text-[12px] text-on-surface-variant">{{ i.detail }}@if (i.latency_ms !== null) { · {{ i.latency_ms }} ms }</span></span>
                          <span [class]="'inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[11px] font-bold ' + status(i.status).tone"><span class="h-1.5 w-1.5 rounded-full" [class]="status(i.status).dot"></span>{{ integrationText(i.status) }}</span>
                        </li>
                      }
                    </ul>
                    <h3 class="mb-1 mt-5 text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Parámetros del servidor</h3>
                    <p class="mb-2 text-[12px] text-on-surface-variant">Solo lectura: se cambian con variables de entorno y requieren reiniciar el servidor. Aquí nunca se muestran secretos.</p>
                    <dl class="divide-y divide-brand-grey/40 rounded-xl border border-brand-grey">
                      @for (p of parameters(h.environment); track p.label) {
                        <div class="flex flex-wrap justify-between gap-2 px-4 py-2"><dt class="text-[13px] text-on-surface-variant">{{ p.label }}</dt><dd class="m-0 text-[13px] font-semibold text-on-surface">{{ p.value }}</dd></div>
                      }
                    </dl>
                  }
                }
              }
            </div>
          </div>
        </div>
      }
      <app-toast-host />
    }
  `,
})
export class SettingsComponent implements OnInit {
  readonly store = inject(SettingsStore);
  private readonly permissions = inject(PermissionsService);

  readonly vm$ = this.store.state$;
  readonly focus = FOCUS;
  readonly card = CARD;
  readonly cardButton = CARD_BUTTON;
  readonly badge = 'flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-[#DDEBF7] text-brand-accentDeep';
  readonly modal = signal<Modal>(null);
  readonly catalog = signal<CatalogTab>('categories');
  readonly catalogTabs: { id: CatalogTab; label: string }[] = [
    { id: 'categories', label: 'Categorías' },
    { id: 'priorities', label: 'Prioridades y SLA' },
  ];
  /** Escribir catálogos y organización exige `priorities.manage`; sin él se ve pero no se edita. */
  readonly canManage = signal(false);

  readonly status = (key: ShownStatus) => STATUS[key];
  readonly integrationText = integrationLabel;
  readonly jobLabel = jobName;
  readonly frequency = frequencyText;
  readonly action = actionLabel;
  readonly attention = attentionTone;
  readonly jobState = jobStatus;
  readonly jobStateLabel = (job: Parameters<typeof jobStatus>[0]): string => jobStatusLabel(jobStatus(job));

  ngOnInit(): void {
    this.store.loadAll();
    void this.permissions.can('configuracion:editar').then((allowed) => this.canManage.set(allowed)).catch(() => this.canManage.set(false));
  }

  @HostListener('document:keydown.escape')
  onEscape(): void {
    this.modal.set(null);
  }

  modalTitle(modal: Exclude<Modal, null>): string {
    return { organization: 'Organización', catalogs: 'Catálogos de mantenimiento', integrations: 'Integraciones y parámetros' }[modal];
  }

  activeCount(items: { is_active: boolean }[]): number {
    return items.filter((item) => item.is_active).length;
  }

  reminders(vm: SettingsState): string {
    const env = vm.health?.environment;
    if (!env) {
      return '—';
    }
    return env.scheduler_enabled ? `Cada ${env.reminder_interval_minutes} min` : 'Desactivados';
  }

  /** Tareas con fallo o con el programador detenido. */
  jobsFailing(health: NonNullable<SettingsState['health']>): number {
    return health.jobs.filter((job) => !job.running || job.last_status === 'error').length;
  }

  parameters(env: NonNullable<SettingsState['health']>['environment']): { label: string; value: string }[] {
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
