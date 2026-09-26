import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { firstValueFrom } from 'rxjs';

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

@Injectable({ providedIn: 'root' })
export class EquipmentService {
  private readonly http = inject(HttpClient);
  private readonly apiUrl = 'http://localhost:8000/equipment';

  async list(): Promise<Equipment[]> {
    return firstValueFrom(this.http.get<Equipment[]>(this.apiUrl));
  }

  async listTypes(): Promise<EquipmentType[]> {
    return firstValueFrom(
      this.http.get<EquipmentType[]>(`${this.apiUrl}/types`),
    );
  }

  async create(payload: EquipmentPayload): Promise<Equipment> {
    return firstValueFrom(this.http.post<Equipment>(this.apiUrl, payload));
  }
}
