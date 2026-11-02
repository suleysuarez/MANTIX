import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

import { apiBaseUrl } from './api.config';

export interface UserRoleRef {
  id: number;
  code: string;
  name: string;
}

export interface ManagedAccount {
  id: number;
  email: string;
  full_name: string;
  phone: string | null;
  employee_code: string | null;
  is_active: boolean;
  roles: UserRoleRef[];
  created_at: string;
  /** Inicio de la última sesión; `null` si la persona nunca ha entrado. */
  last_login_at: string | null;
  /** La persona ya inició sesión alguna vez (su cuenta de acceso está vinculada). */
  linked: boolean;
}

export interface UserCreatePayload {
  email: string;
  full_name: string;
  phone: string | null;
  employee_code: string | null;
  role_ids: number[];
}

/** El nombre no se edita aquí: cada persona lo cambia desde su perfil. */
export type UserUpdatePayload = Partial<Omit<UserCreatePayload, 'role_ids' | 'full_name'>>;

export interface RoleCount {
  code: string;
  name: string;
  count: number;
}

export interface RecentAccess {
  id: number;
  full_name: string;
  email: string;
  last_login_at: string;
}

export interface UsersSummary {
  total: number;
  active: number;
  inactive: number;
  never_signed_in: number;
  without_role: number;
  by_role: RoleCount[];
  recent_access: RecentAccess[];
}

export interface UserQuery {
  search?: string;
  role?: string;
  /** `''` = todos. */
  status?: '' | 'active' | 'inactive';
  /** Fechas ISO completas (inicio y fin del día local). */
  createdFrom?: string;
  createdTo?: string;
  /** `name`, `-created_at`… (prefijo `-` descendente). */
  sort?: string;
  /** Base 1. */
  page?: number;
  size?: number;
}

@Injectable({ providedIn: 'root' })
export class UsersService {
  private readonly http = inject(HttpClient);
  private readonly url = `${apiBaseUrl()}/admin/users`;

  /** Filtros, orden y paginación en el servidor; el total llega en `X-Total-Count`. */
  listPage(query: UserQuery = {}): Observable<{ items: ManagedAccount[]; total: number }> {
    let params = new HttpParams();
    const text: [string, string | undefined][] = [
      ['search', query.search], ['role', query.role], ['created_from', query.createdFrom],
      ['created_to', query.createdTo], ['sort', query.sort],
    ];
    for (const [name, value] of text) {
      if (value) {
        params = params.set(name, value);
      }
    }
    if (query.status) {
      params = params.set('is_active', query.status === 'active');
    }
    if (query.page !== undefined) {
      params = params.set('page', query.page);
    }
    if (query.size !== undefined) {
      params = params.set('size', query.size);
    }
    return this.http.get<ManagedAccount[]>(this.url, { params, observe: 'response' }).pipe(
      map((response) => {
        const items = response.body ?? [];
        const total = Number(response.headers.get('X-Total-Count'));
        return { items, total: Number.isFinite(total) && total >= items.length ? total : items.length };
      }),
    );
  }

  summary(): Observable<UsersSummary> {
    return this.http.get<UsersSummary>(`${this.url}/summary`);
  }

  create(payload: UserCreatePayload): Observable<ManagedAccount> {
    return this.http.post<ManagedAccount>(this.url, payload);
  }

  update(id: number, payload: UserUpdatePayload): Observable<ManagedAccount> {
    return this.http.patch<ManagedAccount>(`${this.url}/${id}`, payload);
  }

  setActive(id: number, active: boolean): Observable<ManagedAccount> {
    return this.http.post<ManagedAccount>(`${this.url}/${id}/${active ? 'activate' : 'deactivate'}`, {});
  }

  replaceRoles(id: number, roleIds: number[]): Observable<ManagedAccount> {
    return this.http.put<ManagedAccount>(`${this.url}/${id}/roles`, { role_ids: roleIds });
  }

  resetPassword(id: number, password: string): Observable<void> {
    return this.http.post<void>(`${this.url}/${id}/password`, { password });
  }
}
