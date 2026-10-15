import { AsyncPipe, DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, computed, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { Subject, debounceTime, distinctUntilChanged } from 'rxjs';

import { initials } from '../../core/equipment-status';
import { LocalProfileService } from '../../core/local-profile.service';
import { ManagedAccount } from '../../core/users.service';
import { USERS_PAGE_SIZE, UsersState, UsersStore } from '../../core/users.store';
import { DateRangeFilterComponent } from '../../shared/date-range-filter.component';
import { PaginationComponent } from '../../shared/pagination.component';
import { ToastHostComponent } from '../../shared/toast-host.component';
import { ExportDrawerComponent } from '../export/export-drawer.component';
import { ExportFilterValues } from '../export/export-model';
import { PasswordModalComponent } from './password-modal.component';
import { UserFormModalComponent } from './user-form-modal.component';
import { ACCESS_LABEL, ACCESS_STYLES, accessState, lastAccessText, roleNames } from './users-ui';

const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';
const FIELD = `w-full rounded-lg border border-outline bg-surface-container-lowest px-3 py-2 text-[13px] text-on-surface ${FOCUS}`;
const ICON_BUTTON = `flex h-8 w-8 items-center justify-center rounded-lg bg-transparent !text-on-surface-variant transition-colors hover:bg-surface-container disabled:opacity-40 ${FOCUS}`;

type Modal =
  | { kind: 'create' }
  | { kind: 'edit'; user: ManagedAccount }
  | { kind: 'password'; user: ManagedAccount }
  | { kind: 'toggle'; user: ManagedAccount }
  | null;

/**
 * Usuarios (solo `users.manage`): indicadores propios, filtros, tabla del servidor con orden y
 * paginación, y las acciones sobre cada cuenta. Las cuentas nunca se borran: se desactivan.
 */
@Component({
  selector: 'app-users',
  standalone: true,
  imports: [AsyncPipe, DatePipe, DateRangeFilterComponent, PaginationComponent, ToastHostComponent, ExportDrawerComponent, UserFormModalComponent, PasswordModalComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (vm$ | async; as vm) {
      <div class="space-y-4">
        <header class="relative overflow-hidden rounded-2xl bg-gradient-to-r from-brand-sidebar to-primary-container px-6 py-5 md:px-8">
          <div class="flex flex-col gap-2.5 md:flex-row md:items-end md:justify-between">
            <div class="space-y-2">
              <span class="glass inline-flex w-fit items-center gap-2 rounded-full px-3 py-1 text-[11px] font-bold uppercase tracking-[0.08em] text-brand-accentDeep">
                <span class="h-2 w-2 rounded-full bg-brand-mustard"></span> Cuentas y accesos
              </span>
              <h1 class="text-[24px] font-extrabold uppercase leading-tight tracking-tight text-white">Usuarios <span class="text-brand-accentLight">y roles</span></h1>
              <p class="max-w-xl text-[13px] leading-snug text-brand-grey">Registra a las personas, define qué puede hacer cada una y desactiva las cuentas que ya no deben entrar.</p>
            </div>
            <div class="flex flex-wrap items-center gap-3">
              <button type="button" (click)="modal.set({ kind: 'create' })" class="glass-btn flex items-center gap-1.5 rounded-xl px-5 py-2.5 text-[13px] font-bold transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white">
                <span class="material-symbols-outlined text-[20px]" aria-hidden="true">person_add</span> Nuevo usuario
              </button>
              <button type="button" (click)="exportOpen.set(true)" class="glass flex items-center gap-1.5 rounded-xl bg-transparent px-4 py-2.5 text-[13px] font-bold !text-brand-accentDeep transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white">
                <span class="material-symbols-outlined text-[18px]" aria-hidden="true">download</span> Exportar
              </button>
            </div>
          </div>
        </header>

        <!-- Indicadores propios: estado de las cuentas, usuarios por rol y últimos accesos -->
        <section class="grid grid-cols-1 gap-3 lg:grid-cols-3" aria-label="Indicadores" [attr.aria-busy]="vm.summaryLoading">
          <article class="glass rounded-2xl p-4">
            <h2 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Cuentas</h2>
            @if (vm.summary; as s) {
              <p class="mt-1 text-[32px] font-extrabold leading-none text-on-surface">{{ s.total }}</p>
              <div class="mt-3 h-2 overflow-hidden rounded-full bg-surface-container" role="img" [attr.aria-label]="s.active + ' activos y ' + s.inactive + ' inactivos'">
                <div class="h-full bg-[#10B981]" [style.width.%]="percent(s.active, s.total)"></div>
              </div>
              <dl class="mt-3 grid grid-cols-2 gap-x-3 gap-y-1 text-[12px]">
                <dt class="text-on-surface-variant">Activas</dt><dd class="m-0 text-right font-bold text-on-surface">{{ s.active }}</dd>
                <dt class="text-on-surface-variant">Inactivas</dt><dd class="m-0 text-right font-bold text-on-surface">{{ s.inactive }}</dd>
                <dt class="text-on-surface-variant">Sin primer ingreso</dt><dd class="m-0 text-right font-bold text-on-surface">{{ s.never_signed_in }}</dd>
                <dt class="text-on-surface-variant">Activas sin rol</dt><dd class="m-0 text-right font-bold text-on-surface">{{ s.without_role }}</dd>
              </dl>
            } @else {
              <div class="mt-2 h-24 animate-pulse rounded-lg bg-surface-container motion-reduce:animate-none"></div>
            }
          </article>

          <article class="glass rounded-2xl p-4">
            <h2 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Usuarios activos por rol</h2>
            @if (vm.summary; as s) {
              <ul class="mt-3 space-y-2">
                @for (r of s.by_role; track r.code) {
                  <li>
                    <div class="flex items-center justify-between text-[12px]">
                      <span class="font-semibold text-on-surface">{{ r.name }}</span>
                      <span class="font-bold text-on-surface">{{ r.count }}</span>
                    </div>
                    <div class="mt-1 h-1.5 overflow-hidden rounded-full bg-surface-container" aria-hidden="true">
                      <div class="h-full bg-brand-accentDeep" [style.width.%]="percent(r.count, maxRole(s.by_role))"></div>
                    </div>
                  </li>
                }
              </ul>
            } @else {
              <div class="mt-2 h-24 animate-pulse rounded-lg bg-surface-container motion-reduce:animate-none"></div>
            }
          </article>

          <article class="glass rounded-2xl p-4">
            <h2 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Últimos accesos</h2>
            @if (vm.summary; as s) {
              <ol class="mt-3 space-y-2">
                @for (a of s.recent_access; track a.id) {
                  <li class="flex items-center gap-2">
                    <span class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[linear-gradient(135deg,#ADD7F6,#A2D2FF)] text-[11px] font-bold text-[#3E5C76]" aria-hidden="true">{{ initialsOf(a.full_name) }}</span>
                    <span class="min-w-0 flex-1 truncate text-[12px] font-semibold text-on-surface">{{ a.full_name }}</span>
                    <span class="shrink-0 text-[11px] text-on-surface-variant">{{ access(a.last_login_at) }}</span>
                  </li>
                } @empty {
                  <li class="text-[12px] text-on-surface-variant">Todavía nadie ha iniciado sesión.</li>
                }
              </ol>
            } @else {
              <div class="mt-2 h-24 animate-pulse rounded-lg bg-surface-container motion-reduce:animate-none"></div>
            }
          </article>
        </section>

        <!-- Filtros -->
        <form class="glass rounded-2xl p-4" aria-label="Filtros de usuarios" (submit)="$event.preventDefault()">
          <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-[minmax(0,2fr)_repeat(2,minmax(0,1fr))_auto]">
            <div>
              <label for="us-search" class="sr-only">Buscar</label>
              <input id="us-search" type="search" [class]="field" placeholder="Buscar por nombre, correo o código" maxlength="100" autocomplete="off"
                [value]="vm.filters.search" (input)="search$.next($any($event.target).value)" />
            </div>
            <div>
              <label for="us-role" class="sr-only">Rol</label>
              <select id="us-role" [class]="field" (change)="store.setFilters({ role: $any($event.target).value })">
                <option value="" [selected]="!vm.filters.role">Todos los roles</option>
                @for (r of vm.roles; track r.id) { <option [value]="r.code" [selected]="vm.filters.role === r.code">{{ r.name }}</option> }
              </select>
            </div>
            <div>
              <label for="us-status" class="sr-only">Estado</label>
              <select id="us-status" [class]="field" (change)="store.setFilters({ status: $any($event.target).value })">
                <option value="" [selected]="!vm.filters.status">Todos los estados</option>
                <option value="active" [selected]="vm.filters.status === 'active'">Activos</option>
                <option value="inactive" [selected]="vm.filters.status === 'inactive'">Inactivos</option>
              </select>
            </div>
            <button type="button" (click)="store.clearFilters()" [disabled]="!hasFilters(vm)"
              class="rounded-lg bg-transparent px-3 py-2 text-[13px] font-semibold !text-brand-accentDeep hover:bg-surface-container disabled:opacity-40 {{ focus }}">Limpiar</button>
          </div>
          <div class="mt-3">
            <app-date-range-filter [inline]="true" label="Fecha de creación" [from]="vm.filters.createdFrom" [to]="vm.filters.createdTo"
              (rangeChange)="store.setFilters({ createdFrom: $event.from, createdTo: $event.to })" />
          </div>
        </form>

        <!-- Tabla -->
        <section class="min-w-0 space-y-3" aria-label="Usuarios" [attr.aria-busy]="vm.loading">
          @if (vm.error) {
            <p role="alert" class="flex flex-wrap items-center gap-3 rounded-lg bg-error-container px-4 py-3 text-[13px] text-on-error-container">
              {{ vm.error }}
              <button type="button" (click)="store.load()" class="rounded-lg bg-transparent px-2 py-1 text-[13px] font-bold underline {{ focus }}">Reintentar</button>
            </p>
          }
          @if (vm.users.length) {
            <div class="glass overflow-x-auto rounded-2xl">
              <table class="w-full min-w-[56rem] text-left text-[13px]">
                <caption class="sr-only">Usuarios registrados</caption>
                <thead>
                  <tr class="border-b border-brand-grey/70 text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">
                    <th scope="col" class="px-3 py-2" [attr.aria-sort]="ariaSort(vm, 'name')"><button type="button" (click)="sortBy(vm, 'name')" [class]="sortButton">Usuario {{ arrow(vm, 'name') }}</button></th>
                    <th scope="col" class="px-3 py-2">Roles</th>
                    <th scope="col" class="px-3 py-2" [attr.aria-sort]="ariaSort(vm, 'is_active')"><button type="button" (click)="sortBy(vm, 'is_active')" [class]="sortButton">Estado {{ arrow(vm, 'is_active') }}</button></th>
                    <th scope="col" class="px-3 py-2" [attr.aria-sort]="ariaSort(vm, 'last_login_at')"><button type="button" (click)="sortBy(vm, 'last_login_at')" [class]="sortButton">Último acceso {{ arrow(vm, 'last_login_at') }}</button></th>
                    <th scope="col" class="px-3 py-2" [attr.aria-sort]="ariaSort(vm, 'created_at')"><button type="button" (click)="sortBy(vm, 'created_at')" [class]="sortButton">Creado {{ arrow(vm, 'created_at') }}</button></th>
                    <th scope="col" class="px-3 py-2 text-right">Acciones</th>
                  </tr>
                </thead>
                <tbody>
                  @for (u of vm.users; track u.id) {
                    <tr class="border-b border-brand-grey/40 last:border-0">
                      <td class="px-3 py-2">
                        <div class="flex items-center gap-2">
                          <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-[linear-gradient(135deg,#ADD7F6,#A2D2FF)] text-[12px] font-bold text-[#3E5C76]" aria-hidden="true">{{ initialsOf(u.full_name) }}</span>
                          <div class="min-w-0">
                            <p class="truncate font-semibold text-on-surface">{{ u.full_name }}</p>
                            <p class="truncate text-[12px] text-on-surface-variant">{{ u.email }}@if (u.employee_code) { · {{ u.employee_code }} }</p>
                          </div>
                        </div>
                      </td>
                      <td class="px-3 py-2 text-on-surface">{{ rolesOf(u) }}</td>
                      <td class="px-3 py-2">
                        <span class="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[12px] font-bold" [class]="styleOf(u).chip">
                          <span class="h-1.5 w-1.5 rounded-full" [class]="styleOf(u).dot"></span>{{ labelOf(u) }}
                        </span>
                      </td>
                      <td class="px-3 py-2 text-on-surface-variant" [title]="u.last_login_at ? (u.last_login_at | date: 'dd/MM/yyyy HH:mm') : ''">{{ access(u.last_login_at) }}</td>
                      <td class="px-3 py-2 font-mono text-[12px] text-on-surface-variant">{{ u.created_at | date: 'dd/MM/yyyy' }}</td>
                      <td class="px-3 py-2">
                        <div class="flex justify-end gap-1">
                          <button type="button" [class]="iconButton" [attr.aria-label]="'Editar a ' + u.full_name" title="Editar" (click)="modal.set({ kind: 'edit', user: u })">
                            <span class="material-symbols-outlined text-[18px]" aria-hidden="true">edit</span>
                          </button>
                          <button type="button" [class]="iconButton" [attr.aria-label]="'Restablecer la contraseña de ' + u.full_name" title="Restablecer contraseña"
                            [disabled]="!canReset(u)" (click)="modal.set({ kind: 'password', user: u })">
                            <span class="material-symbols-outlined text-[18px]" aria-hidden="true">key</span>
                          </button>
                          <button type="button" [class]="iconButton" [disabled]="isSelf(u)"
                            [attr.aria-label]="(u.is_active ? 'Desactivar a ' : 'Activar a ') + u.full_name" [title]="isSelf(u) ? 'No puedes desactivar tu propia cuenta' : u.is_active ? 'Desactivar' : 'Activar'"
                            (click)="u.is_active ? modal.set({ kind: 'toggle', user: u }) : activate(u)">
                            <span class="material-symbols-outlined text-[18px]" aria-hidden="true">{{ u.is_active ? 'person_off' : 'person_check' }}</span>
                          </button>
                        </div>
                      </td>
                    </tr>
                  }
                </tbody>
              </table>
            </div>
            <app-pagination noun="usuarios" [page]="vm.page" [pageSize]="pageSize" [total]="vm.total" [loading]="vm.loading" (pageChange)="store.setPage($event)" />
          } @else if (vm.loading) {
            <div class="space-y-2" role="status" aria-label="Cargando usuarios">
              @for (n of skeleton; track n) { <div class="h-14 animate-pulse rounded-xl bg-surface-container motion-reduce:animate-none"></div> }
            </div>
          } @else if (!vm.error) {
            <div class="glass flex flex-col items-center gap-2 rounded-2xl px-6 py-12 text-center">
              <span class="material-symbols-outlined text-[40px] text-on-surface-variant" aria-hidden="true">group_off</span>
              <h2 class="text-[15px] font-bold text-on-surface">{{ hasFilters(vm) ? 'Ningún usuario coincide con los filtros' : 'Aún no hay usuarios' }}</h2>
              <p class="max-w-sm text-[13px] text-on-surface-variant">{{ hasFilters(vm) ? 'Prueba con otra búsqueda o limpia los filtros.' : 'Registra a la primera persona con «Nuevo usuario».' }}</p>
            </div>
          }
        </section>
      </div>

      @switch (modal()?.kind) {
        @case ('create') { <app-user-form-modal [roles]="vm.roles" [busy]="vm.busy" (closed)="modal.set(null)" /> }
        @case ('edit') { @if (editing(); as user) { <app-user-form-modal [user]="user" [roles]="vm.roles" [busy]="vm.busy" (closed)="modal.set(null)" /> } }
        @case ('password') { @if (editing(); as user) { <app-password-modal [user]="user" [busy]="vm.busy" (closed)="modal.set(null)" /> } }
        @case ('toggle') {
          @if (editing(); as user) {
            <div class="fixed inset-0 z-[55] flex items-end justify-center p-0 sm:items-center sm:p-4">
              <div class="absolute inset-0 bg-brand-navy/50" (click)="modal.set(null)" aria-hidden="true"></div>
              <div class="glass relative w-full max-w-md rounded-t-2xl p-5 sm:rounded-2xl" role="alertdialog" aria-modal="true" aria-labelledby="us-off-title" aria-describedby="us-off-text">
                <h2 id="us-off-title" class="text-[16px] font-bold text-on-surface">¿Desactivar a {{ user.full_name }}?</h2>
                <p id="us-off-text" class="mt-2 text-[13px] text-on-surface-variant">No podrá iniciar sesión. Su historial se conserva y puedes reactivarla cuando quieras.</p>
                <div class="mt-4 flex justify-end gap-2">
                  <button type="button" (click)="modal.set(null)" class="rounded-lg bg-transparent px-4 py-2 text-[13px] font-semibold !text-on-surface-variant hover:bg-surface-container {{ focus }}">Cancelar</button>
                  <button type="button" [disabled]="vm.busy" (click)="deactivate(user)" class="rounded-xl bg-[#B91C1C] px-5 py-2 text-[13px] font-bold !text-white hover:bg-[#991B1B] disabled:opacity-50 {{ focus }}">Desactivar</button>
                </div>
              </div>
            </div>
          }
        }
      }

      @if (exportOpen()) {
        <app-export-drawer report="users" title="usuarios" [initial]="exportInitial(vm)" [filterKinds]="['users']" [roleOptions]="roleChoices(vm)"
          (closed)="exportOpen.set(false)" />
      }
      <app-toast-host />
    }
  `,
})
export class UsersComponent implements OnInit {
  readonly store = inject(UsersStore);
  private readonly profile = inject(LocalProfileService);
  private readonly destroyRef = inject(DestroyRef);

  readonly vm$ = this.store.state$;
  readonly modal = signal<Modal>(null);
  readonly exportOpen = signal(false);
  readonly search$ = new Subject<string>();
  readonly selfId = signal<number | null>(null);

  readonly focus = FOCUS;
  readonly field = FIELD;
  readonly iconButton = ICON_BUTTON;
  readonly sortButton = `${FOCUS} bg-transparent p-0 text-[11px] font-bold uppercase tracking-wider !text-on-surface-variant hover:!text-on-surface`;
  readonly pageSize = USERS_PAGE_SIZE;
  readonly skeleton = [1, 2, 3, 4, 5];
  readonly initialsOf = initials;
  readonly rolesOf = roleNames;
  readonly access = (value: string | null): string => lastAccessText(value);

  /** El usuario del modal abierto (para `@case`, que no estrecha el tipo de la unión). */
  readonly editing = computed(() => {
    const modal = this.modal();
    return modal && modal.kind !== 'create' ? modal.user : null;
  });

  ngOnInit(): void {
    this.store.load();
    this.search$
      .pipe(debounceTime(300), distinctUntilChanged(), takeUntilDestroyed(this.destroyRef))
      .subscribe((search) => this.store.setFilters({ search }));
    this.profile
      .getProfile()
      .then((me) => this.selfId.set(me.id))
      .catch(() => undefined);
  }

  styleOf(user: ManagedAccount): { chip: string; dot: string } {
    return ACCESS_STYLES[accessState(user)];
  }

  labelOf(user: ManagedAccount): string {
    return ACCESS_LABEL[accessState(user)];
  }

  isSelf(user: ManagedAccount): boolean {
    return this.selfId() === user.id;
  }

  /** Solo se restablece la contraseña de otra persona, activa y que ya inició sesión. */
  canReset(user: ManagedAccount): boolean {
    return !this.isSelf(user) && user.is_active && user.linked;
  }

  percent(value: number, max: number): number {
    return max > 0 ? Math.round((value / max) * 100) : 0;
  }

  maxRole(counts: { count: number }[]): number {
    return Math.max(0, ...counts.map((item) => item.count));
  }

  hasFilters(vm: UsersState): boolean {
    const f = vm.filters;
    return !!(f.search || f.role || f.status || f.createdFrom || f.createdTo);
  }

  activate(user: ManagedAccount): void {
    this.store.setActive(user, true).subscribe();
  }

  deactivate(user: ManagedAccount): void {
    this.store.setActive(user, false).subscribe(() => this.modal.set(null));
  }

  sortBy(vm: UsersState, field: string): void {
    this.store.setFilters({ sort: vm.filters.sort === field ? `-${field}` : field });
  }

  arrow(vm: UsersState, field: string): string {
    return vm.filters.sort === field ? '▲' : vm.filters.sort === `-${field}` ? '▼' : '';
  }

  ariaSort(vm: UsersState, field: string): 'ascending' | 'descending' | 'none' {
    return vm.filters.sort === field ? 'ascending' : vm.filters.sort === `-${field}` ? 'descending' : 'none';
  }

  roleChoices(vm: UsersState): { value: string; label: string }[] {
    return vm.roles.map((role) => ({ value: role.code, label: role.name }));
  }

  exportInitial(vm: UsersState): ExportFilterValues {
    const f = vm.filters;
    return {
      statuses: [], priorities: [], categories: [], technicianIds: [],
      dateFrom: f.createdFrom, dateTo: f.createdTo,
      search: f.search, role: f.role, active: f.status,
    };
  }
}
