import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { firstValueFrom } from 'rxjs';

export interface LocalRole {
  code: string;
  name: string;
}

export interface LocalPermission {
  code: string;
  name: string;
}

export interface LocalProfile {
  id: number;
  email: string;
  full_name: string;
  employee_code: string | null;
  is_active: boolean;
  roles: LocalRole[];
  permissions: LocalPermission[];
}

@Injectable({ providedIn: 'root' })
export class LocalProfileService {
  private readonly http = inject(HttpClient);
  private profile: LocalProfile | null = null;

  async getProfile(): Promise<LocalProfile> {
    if (!this.profile) {
      this.profile = await firstValueFrom(
        this.http.get<LocalProfile>('http://localhost:8000/auth/me'),
      );
    }
    return this.profile;
  }

  clear(): void {
    this.profile = null;
  }
}
