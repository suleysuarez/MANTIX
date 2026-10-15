import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { apiBaseUrl } from './api.config';

export interface Technician {
  id: number;
  user_id: number;
  full_name: string;
  email: string;
  employee_code: string | null;
  specialization: string | null;
  is_available: boolean;
  hourly_rate: string | null;
  /** Alta del perfil: el primer evento de su historial. */
  created_at: string;
}

export interface TechnicianPayload {
  user_id: number;
  specialization: string | null;
  hourly_rate: number | null;
}

export interface TechnicianUpdatePayload {
  specialization?: string | null;
  is_available?: boolean;
  hourly_rate?: number | null;
}

/** Carga de trabajo de un técnico en la ventana indicada (`/dashboard/workload`). */
export interface TechnicianWorkload {
  technician_id: number;
  full_name: string;
  is_available: boolean;
  open_tickets: number;
  resolved_in_window: number;
}

export interface WorkloadResponse {
  window_days: number;
  scope: string;
  technicians: TechnicianWorkload[];
}

@Injectable({ providedIn: 'root' })
export class TechniciansService {
  private readonly http = inject(HttpClient);
  private readonly url = `${apiBaseUrl()}/technicians`;

  list(): Observable<Technician[]> {
    return this.http.get<Technician[]>(this.url);
  }

  create(payload: TechnicianPayload): Observable<Technician> {
    return this.http.post<Technician>(this.url, payload);
  }

  update(id: number, payload: TechnicianUpdatePayload): Observable<Technician> {
    return this.http.patch<Technician>(`${this.url}/${id}`, payload);
  }

  setAvailability(id: number, isAvailable: boolean): Observable<Technician> {
    return this.update(id, { is_available: isAvailable });
  }

  workload(days = 30): Observable<WorkloadResponse> {
    return this.http.get<WorkloadResponse>(`${apiBaseUrl()}/dashboard/workload`, { params: { days } });
  }
}
