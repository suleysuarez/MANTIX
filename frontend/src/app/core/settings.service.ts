import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { apiBaseUrl } from './api.config';

export type HealthStatus = 'ok' | 'warning' | 'error' | 'disabled';

export interface SystemHealth {
  generated_at: string;
  overall: 'ok' | 'warning' | 'error';
  environment: {
    name: string;
    version: string;
    rate_limit_per_minute: number;
    max_upload_mb: number;
    reminder_interval_minutes: number;
    log_level: string;
    scheduler_enabled: boolean;
  };
  users: { total: number; active: number; inactive: number; without_role: number };
  roles: { id: number; code: string; name: string; is_active: boolean; users: number; permissions: number }[];
  audit: {
    last_24h: number;
    recent: { id: number; action: string; entity_type: string; entity_id: number | null; by: string | null; at: string }[];
  };
  jobs: {
    id: string;
    name: string;
    running: boolean;
    interval_minutes: number | null;
    next_run_at: string | null;
    last_run_at: string | null;
    last_status: 'ok' | 'error' | 'never';
    last_detail: string | null;
  }[];
  integrations: { key: string; name: string; status: HealthStatus; detail: string; latency_ms: number | null }[];
}

export interface CategoryAdmin {
  id: number;
  code: string;
  name: string;
  is_active: boolean;
  usage: number;
  created_at: string;
}

export interface PriorityAdmin {
  id: number;
  code: string;
  name: string;
  description: string | null;
  level: number;
  sla_hours: number | null;
  is_active: boolean;
}

export interface PriorityPayload {
  name?: string;
  description?: string | null;
  level?: number;
  sla_hours?: number | null;
  is_active?: boolean;
}

@Injectable({ providedIn: 'root' })
export class SettingsService {
  private readonly http = inject(HttpClient);
  private readonly base = `${apiBaseUrl()}`;

  health(): Observable<SystemHealth> {
    return this.http.get<SystemHealth>(`${this.base}/settings/health`);
  }

  categories(): Observable<CategoryAdmin[]> {
    return this.http.get<CategoryAdmin[]>(`${this.base}/settings/categories`);
  }

  createCategory(body: { code: string; name: string }): Observable<CategoryAdmin> {
    return this.http.post<CategoryAdmin>(`${this.base}/settings/categories`, body);
  }

  updateCategory(id: number, body: { name?: string; is_active?: boolean }): Observable<CategoryAdmin> {
    return this.http.patch<CategoryAdmin>(`${this.base}/settings/categories/${id}`, body);
  }

  deleteCategory(id: number): Observable<void> {
    return this.http.delete<void>(`${this.base}/settings/categories/${id}`);
  }

  priorities(): Observable<PriorityAdmin[]> {
    return this.http.get<PriorityAdmin[]>(`${this.base}/priorities`, { params: new HttpParams().set('include_inactive', true) });
  }

  updatePriority(id: number, body: PriorityPayload): Observable<PriorityAdmin> {
    return this.http.patch<PriorityAdmin>(`${this.base}/priorities/${id}`, body);
  }
}
