import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

import { apiBaseUrl } from './api.config';

export interface ProfileData {
  id: number;
  /** Solo lectura: es la identidad de acceso. */
  email: string;
  full_name: string;
  phone: string | null;
  employee_code: string | null;
  roles: { code: string; name: string }[];
  has_avatar: boolean;
  /** Cambia con cada foto nueva (para no servir la anterior desde caché). */
  avatar_version: number | null;
  last_login_at: string | null;
  created_at: string;
}

export interface ProfileUpdatePayload {
  full_name?: string;
  phone?: string | null;
}

export type HistoryKind = 'session' | 'profile' | 'security' | 'activity';

export interface HistoryEntry {
  id: number;
  action: string;
  kind: HistoryKind;
  entity_type: string;
  entity_id: number | null;
  /** Quién lo hizo cuando fue otra persona (p. ej. un administrador); `null` si fuiste tú. */
  actor_name: string | null;
  ip_address: string | null;
  created_at: string;
}

export interface HistoryQuery {
  kind?: HistoryKind | '';
  /** Fechas ISO completas (inicio y fin del día local). */
  dateFrom?: string;
  dateTo?: string;
  /** Base 1. */
  page?: number;
  size?: number;
}

@Injectable({ providedIn: 'root' })
export class ProfileService {
  private readonly http = inject(HttpClient);
  private readonly url = `${apiBaseUrl()}/profile`;

  get(): Observable<ProfileData> {
    return this.http.get<ProfileData>(this.url);
  }

  update(payload: ProfileUpdatePayload): Observable<ProfileData> {
    return this.http.patch<ProfileData>(this.url, payload);
  }

  uploadAvatar(file: File): Observable<ProfileData> {
    const body = new FormData();
    body.append('file', file, file.name);
    return this.http.put<ProfileData>(`${this.url}/avatar`, body);
  }

  /** La foto va con el token de acceso, así que se pide como blob y se muestra con una URL local. */
  avatar(): Observable<Blob> {
    return this.http.get(`${this.url}/avatar`, { responseType: 'blob' });
  }

  removeAvatar(): Observable<ProfileData> {
    return this.http.delete<ProfileData>(`${this.url}/avatar`);
  }

  changePassword(currentPassword: string, newPassword: string): Observable<void> {
    return this.http.post<void>(`${this.url}/password`, { current_password: currentPassword, new_password: newPassword });
  }

  /** Historial propio con filtros y paginación en el servidor; el total llega en `X-Total-Count`. */
  history(query: HistoryQuery = {}): Observable<{ items: HistoryEntry[]; total: number }> {
    let params = new HttpParams();
    if (query.kind) {
      params = params.set('kind', query.kind);
    }
    if (query.dateFrom) {
      params = params.set('date_from', query.dateFrom);
    }
    if (query.dateTo) {
      params = params.set('date_to', query.dateTo);
    }
    if (query.page !== undefined) {
      params = params.set('page', query.page);
    }
    if (query.size !== undefined) {
      params = params.set('size', query.size);
    }
    return this.http.get<HistoryEntry[]>(`${this.url}/history`, { params, observe: 'response' }).pipe(
      map((response) => {
        const items = response.body ?? [];
        const total = Number(response.headers.get('X-Total-Count'));
        return { items, total: Number.isFinite(total) && total >= items.length ? total : items.length };
      }),
    );
  }
}
