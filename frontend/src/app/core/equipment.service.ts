import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

import { apiBaseUrl } from './api.config';

export interface EquipmentType {
  id: number;
  code: string;
  name: string;
}

export interface LocationItem {
  id: number;
  code: string;
  name: string;
  kind: string;
  parent_id: number | null;
}

export interface LocationBrief {
  id: number;
  code: string;
  name: string;
}

export interface CustodianBrief {
  id: number;
  full_name: string;
  email: string;
}

export interface LastMaintenance {
  performed_at: string;
  work_type: string;
  result: string;
  technician_name: string;
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
  current_location: LocationBrief | null;
  current_custodian: CustodianBrief | null;
  last_maintenance: LastMaintenance | null;
}

/** Cuerpo de alta/edición. En edición el código de activo no se envía (la API no lo permite cambiar). */
export interface EquipmentPayload {
  asset_tag: string;
  serial_number: string | null;
  equipment_type_id: number;
  brand: string;
  model: string;
  description: string | null;
  status: string;
  purchase_date: string | null;
  purchase_cost: number | null;
  warranty_start_date: string | null;
  warranty_end_date: string | null;
}

export type EquipmentUpdatePayload = Omit<EquipmentPayload, 'asset_tag'>;

export interface EquipmentSummary {
  total: number;
  by_status: Record<string, number>;
}

export interface CustodianCandidate {
  id: number;
  full_name: string;
  email: string;
}

export interface Attachment {
  id: number;
  file_name: string;
  mime_type: string;
  file_size: number;
  uploaded_by_user_id: number | null;
  created_at: string;
}

export interface EquipmentQuery {
  search?: string;
  /** Un estado o varios separados por comas. */
  status?: string;
  equipmentTypeId?: number | null;
  locationId?: number | null;
  sort?: string;
  /** Base 1. */
  page?: number;
  size?: number;
}

export interface EquipmentPage {
  items: Equipment[];
  total: number;
}

export type ReportFormat = 'xlsx' | 'csv' | 'pdf';

@Injectable({ providedIn: 'root' })
export class EquipmentService {
  private readonly http = inject(HttpClient);
  private readonly apiUrl = `${apiBaseUrl()}/equipment`;

  /** La API devuelve un array y describe el total en la cabecera `X-Total-Count`. */
  list(query: EquipmentQuery = {}): Observable<EquipmentPage> {
    let params = new HttpParams();
    if (query.search) {
      params = params.set('search', query.search);
    }
    if (query.status) {
      params = params.set('status', query.status);
    }
    if (query.equipmentTypeId) {
      params = params.set('equipment_type_id', query.equipmentTypeId);
    }
    if (query.locationId) {
      params = params.set('location_id', query.locationId);
    }
    if (query.sort) {
      params = params.set('sort', query.sort);
    }
    if (query.page !== undefined) {
      params = params.set('page', query.page);
    }
    if (query.size !== undefined) {
      params = params.set('size', query.size);
    }
    return this.http.get<Equipment[]>(this.apiUrl, { params, observe: 'response' }).pipe(
      map((response) => {
        const items = response.body ?? [];
        const total = Number(response.headers.get('X-Total-Count'));
        return { items, total: Number.isFinite(total) && total >= items.length ? total : items.length };
      }),
    );
  }

  /** Hasta `limit` equipos sin paginar (listas desplegables y métricas del dashboard). */
  listAll(limit = 500): Observable<Equipment[]> {
    return this.list({ size: limit }).pipe(map((page) => page.items));
  }

  get(id: number): Observable<Equipment> {
    return this.http.get<Equipment>(`${this.apiUrl}/${id}`);
  }

  summary(): Observable<EquipmentSummary> {
    return this.http.get<EquipmentSummary>(`${this.apiUrl}/summary`);
  }

  listTypes(): Observable<EquipmentType[]> {
    return this.http.get<EquipmentType[]>(`${this.apiUrl}/types`);
  }

  listLocations(): Observable<LocationItem[]> {
    return this.http.get<LocationItem[]>(`${apiBaseUrl()}/locations`, { params: { size: 500 } });
  }

  create(payload: EquipmentPayload): Observable<Equipment> {
    return this.http.post<Equipment>(this.apiUrl, payload);
  }

  update(id: number, payload: EquipmentUpdatePayload): Observable<Equipment> {
    return this.http.patch<Equipment>(`${this.apiUrl}/${id}`, payload);
  }

  assignLocation(id: number, locationId: number): Observable<Equipment> {
    return this.http.post<Equipment>(`${this.apiUrl}/${id}/location`, { location_id: locationId });
  }

  assignCustody(id: number, userId: number): Observable<Equipment> {
    return this.http.post<Equipment>(`${this.apiUrl}/${id}/custody`, { assigned_to_user_id: userId });
  }

  custodianCandidates(search: string): Observable<CustodianCandidate[]> {
    return this.http.get<CustodianCandidate[]>(`${this.apiUrl}/custodian-candidates`, {
      params: search ? { search } : {},
    });
  }

  listAttachments(id: number): Observable<Attachment[]> {
    return this.http.get<Attachment[]>(`${this.apiUrl}/${id}/attachments`);
  }

  uploadAttachment(id: number, file: File): Observable<Attachment> {
    const body = new FormData();
    body.append('file', file, file.name);
    return this.http.post<Attachment>(`${this.apiUrl}/${id}/attachments`, body);
  }

  downloadAttachment(attachmentId: number): Observable<Blob> {
    return this.http.get(`${apiBaseUrl()}/attachments/${attachmentId}/download`, { responseType: 'blob' });
  }

  /** Reporte del inventario con los mismos filtros de la pantalla (permiso `reports.read`). */
  exportReport(format: ReportFormat, query: EquipmentQuery = {}): Observable<Blob> {
    let params = new HttpParams().set('format', format);
    if (query.status) {
      params = params.set('status', query.status);
    }
    if (query.equipmentTypeId) {
      params = params.set('equipment_type_id', query.equipmentTypeId);
    }
    return this.http.get(`${apiBaseUrl()}/reports/equipment`, { params, responseType: 'blob' });
  }
}
