import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable, of } from 'rxjs';
import { catchError, map, tap } from 'rxjs/operators';

import { dateRangeError } from '../shared/date-range';
import { dayBoundaryIso } from '../features/reports/report-filters';
import { AdminRole, AdminUsersService } from './admin-users.service';
import { apiErrorMessage, apiFieldErrors } from './api-errors';
import { ActionResult } from './pending-requests.store';
import { ToastService } from './toast.service';
import {
  ManagedAccount,
  UserCreatePayload,
  UserQuery,
  UsersService,
  UsersSummary,
  UserUpdatePayload,
} from './users.service';

export const USERS_PAGE_SIZE = 10;

export interface UserFilters {
  search: string;
  role: string;
  status: '' | 'active' | 'inactive';
  /** `yyyy-MM-dd` (día local); vacío = sin límite. */
  createdFrom: string;
  createdTo: string;
  /** `name`, `-created_at`… (prefijo `-` descendente). */
  sort: string;
}

export const EMPTY_USER_FILTERS: UserFilters = { search: '', role: '', status: '', createdFrom: '', createdTo: '', sort: 'name' };

export interface UsersState {
  filters: UserFilters;
  /** Problema del rango de fechas; con él no se consulta al servidor. */
  rangeError: string;
  users: ManagedAccount[];
  total: number;
  page: number;
  loading: boolean;
  error: string;
  roles: AdminRole[];
  summary: UsersSummary | null;
  summaryLoading: boolean;
  busy: boolean;
}

const INITIAL: UsersState = {
  filters: EMPTY_USER_FILTERS,
  rangeError: '',
  users: [],
  total: 0,
  page: 1,
  loading: true,
  error: '',
  roles: [],
  summary: null,
  summaryLoading: true,
  busy: false,
};

/** Observer pattern store de la pantalla de usuarios: lista del servidor, indicadores y acciones. */
@Injectable({ providedIn: 'root' })
export class UsersStore {
  private readonly api = inject(UsersService);
  private readonly roleApi = inject(AdminUsersService);
  private readonly toasts = inject(ToastService);
  private readonly subject = new BehaviorSubject<UsersState>(INITIAL);

  readonly state$: Observable<UsersState> = this.subject.asObservable();

  private get value(): UsersState {
    return this.subject.value;
  }

  private patch(changes: Partial<UsersState>): void {
    this.subject.next({ ...this.value, ...changes });
  }

  load(): void {
    this.loadList(1);
    this.loadSummary();
    this.roleApi.listRoles().subscribe({
      next: (roles) => this.patch({ roles }),
      error: () => undefined, // sin roles no se puede crear, pero la lista sigue sirviendo
    });
  }

  setFilters(changes: Partial<UserFilters>): void {
    const filters = { ...this.value.filters, ...changes };
    const rangeError = dateRangeError(filters.createdFrom, filters.createdTo);
    this.patch({ filters, rangeError });
    if (!rangeError) {
      this.loadList(1);
    }
  }

  clearFilters(): void {
    this.setFilters({ ...EMPTY_USER_FILTERS, sort: this.value.filters.sort });
  }

  setPage(page: number): void {
    if (page >= 1 && !this.value.loading) {
      this.loadList(page);
    }
  }

  create(payload: UserCreatePayload): Observable<ActionResult> {
    return this.run(this.api.create(payload), 'Usuario registrado. Podrá entrar con ese correo.');
  }

  update(id: number, payload: UserUpdatePayload): Observable<ActionResult> {
    return this.run(this.api.update(id, payload), 'Usuario actualizado.');
  }

  replaceRoles(id: number, roleIds: number[]): Observable<ActionResult> {
    return this.run(this.api.replaceRoles(id, roleIds), 'Roles actualizados.');
  }

  setActive(user: ManagedAccount, active: boolean): Observable<ActionResult> {
    return this.run(
      this.api.setActive(user.id, active),
      active ? `${user.full_name} fue activado.` : `${user.full_name} fue desactivado.`,
    );
  }

  resetPassword(id: number, password: string): Observable<ActionResult> {
    return this.run(this.api.resetPassword(id, password), 'Contraseña restablecida.');
  }

  private run<T>(call: Observable<T>, success: string): Observable<ActionResult> {
    if (this.value.busy) {
      return of({ ok: false, fieldErrors: {} });
    }
    this.patch({ busy: true });
    return call.pipe(
      tap(() => this.toasts.success(success)),
      map(() => {
        this.patch({ busy: false });
        this.loadList(this.value.page);
        this.loadSummary();
        return { ok: true, fieldErrors: {} } as ActionResult;
      }),
      catchError((error) => {
        this.patch({ busy: false });
        this.toasts.error(apiErrorMessage(error, 'No se pudo completar la acción.'));
        return of({ ok: false, fieldErrors: apiFieldErrors(error) });
      }),
    );
  }

  private query(page: number): UserQuery {
    const f = this.value.filters;
    return {
      search: f.search.trim() || undefined,
      role: f.role || undefined,
      status: f.status,
      createdFrom: dayBoundaryIso(f.createdFrom, false) ?? undefined,
      createdTo: dayBoundaryIso(f.createdTo, true) ?? undefined,
      sort: f.sort,
      page,
      size: USERS_PAGE_SIZE,
    };
  }

  private loadList(page: number): void {
    this.patch({ loading: true, error: '' });
    this.api.listPage(this.query(page)).subscribe({
      next: ({ items, total }) => {
        if (items.length === 0 && page > 1) {
          this.loadList(page - 1);
          return;
        }
        this.patch({ users: items, total, page, loading: false });
      },
      error: (error) => this.patch({ loading: false, error: apiErrorMessage(error, 'No se pudieron cargar los usuarios.') }),
    });
  }

  private loadSummary(): void {
    this.patch({ summaryLoading: true });
    this.api.summary().subscribe({
      next: (summary) => this.patch({ summary, summaryLoading: false }),
      error: () => this.patch({ summaryLoading: false }),
    });
  }
}
