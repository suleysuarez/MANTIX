import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, tap } from 'rxjs';

import { apiBaseUrl } from './api.config';
import { LocalProfileService } from './local-profile.service';

export interface EffectivePermission {
  code: string;
  source_role_id: number;
  source_role_name: string;
  /** `true` si la concede un rol ancestro y no el propio. */
  inherited: boolean;
}

export interface RoleAdmin {
  id: number;
  code: string;
  name: string;
  description: string | null;
  is_active: boolean;
  /** Roles base: no se eliminan, desactivan ni cambian de padre. */
  is_system: boolean;
  parent_role_id: number | null;
  parent_name: string | null;
  depth: number;
  user_count: number;
  children_count: number;
  own_permissions: string[];
  effective: EffectivePermission[];
}

export interface PermissionInfo {
  code: string;
  name: string;
  module: string;
  description: string | null;
  resource: string | null;
  action: string | null;
}

export interface RoleCreatePayload {
  name: string;
  description: string | null;
  parent_role_id: number | null;
  permissions: string[];
}

export interface RoleUpdatePayload {
  name?: string;
  description?: string | null;
  parent_role_id?: number | null;
  is_active?: boolean;
}

/** Administración de roles y de lo que concede cada uno (solo quien tiene `usuarios:asignar`). */
@Injectable({ providedIn: 'root' })
export class RolesAdminService {
  private readonly http = inject(HttpClient);
  private readonly profile = inject(LocalProfileService);
  private readonly url = `${apiBaseUrl()}/admin`;

  list(): Observable<RoleAdmin[]> {
    return this.http.get<RoleAdmin[]>(`${this.url}/roles/manage`);
  }

  permissions(): Observable<PermissionInfo[]> {
    return this.http.get<PermissionInfo[]>(`${this.url}/permissions`);
  }

  create(payload: RoleCreatePayload): Observable<RoleAdmin> {
    return this.http.post<RoleAdmin>(`${this.url}/roles`, payload).pipe(tap(() => this.profile.clear()));
  }

  update(id: number, payload: RoleUpdatePayload): Observable<RoleAdmin> {
    return this.http.patch<RoleAdmin>(`${this.url}/roles/${id}`, payload).pipe(tap(() => this.profile.clear()));
  }

  setPermissions(id: number, permissions: string[]): Observable<RoleAdmin> {
    return this.http.put<RoleAdmin>(`${this.url}/roles/${id}/permissions`, { permissions }).pipe(tap(() => this.profile.clear()));
  }

  remove(id: number): Observable<void> {
    return this.http.delete<void>(`${this.url}/roles/${id}`).pipe(tap(() => this.profile.clear()));
  }
}
