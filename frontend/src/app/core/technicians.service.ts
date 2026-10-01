import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { apiBaseUrl } from './api.config';

export interface Technician {
  id: number;
  user_id: number;
  specialization: string | null;
  is_available: boolean;
  hourly_rate: string | null;
}

export interface TechnicianPayload {
  user_id: number;
  specialization: string | null;
  hourly_rate: number | null;
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

  setAvailability(id: number, isAvailable: boolean): Observable<Technician> {
    return this.http.patch<Technician>(`${this.url}/${id}`, { is_available: isAvailable });
  }
}
