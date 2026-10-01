import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { apiBaseUrl } from './api.config';

export interface EquipmentType {
  id: number;
  code: string;
  name: string;
}

export interface Equipment {
  id: number;
  asset_tag: string;
  serial_number: string | null;
  equipment_type_id: number;
  equipment_type: EquipmentType;
  brand: string;
  model: string;
  description: string | null;
  status: string;
  purchase_date: string | null;
  purchase_cost: string | null;
  warranty_start_date: string | null;
  warranty_end_date: string | null;
}

export interface EquipmentPayload {
  asset_tag: string;
  serial_number: string | null;
  equipment_type_id: number;
  brand: string;
  model: string;
  description: string | null;
  status: string;
}

export interface EquipmentQuery {
  search?: string;
  status?: string;
  limit?: number;
  offset?: number;
}

@Injectable({ providedIn: 'root' })
export class EquipmentService {
  private readonly http = inject(HttpClient);
  private readonly apiUrl = `${apiBaseUrl()}/equipment`;

  list(query: EquipmentQuery = {}): Observable<Equipment[]> {
    let params = new HttpParams();
    if (query.search) {
      params = params.set('search', query.search);
    }
    if (query.status) {
      params = params.set('status', query.status);
    }
    if (query.limit !== undefined) {
      params = params.set('limit', query.limit);
    }
    if (query.offset !== undefined) {
      params = params.set('offset', query.offset);
    }
    return this.http.get<Equipment[]>(this.apiUrl, { params });
  }

  listTypes(): Observable<EquipmentType[]> {
    return this.http.get<EquipmentType[]>(`${this.apiUrl}/types`);
  }

  create(payload: EquipmentPayload): Observable<Equipment> {
    return this.http.post<Equipment>(this.apiUrl, payload);
  }
}
