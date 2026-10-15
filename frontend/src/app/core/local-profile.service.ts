import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { firstValueFrom } from 'rxjs';

import { apiBaseUrl } from './api.config';

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
        this.http.get<LocalProfile>(`${apiBaseUrl()}/auth/me`),
      );
    }
    return this.profile;
  }

  async can(permission: string): Promise<boolean> {
    const profile = await this.getProfile();
    return profile.permissions.some((item) => item.code === permission);
  }

  /** Mantiene al día el nombre de la copia en memoria cuando la persona lo edita en su perfil. */
  setName(fullName: string): void {
    if (this.profile) {
      this.profile = { ...this.profile, full_name: fullName };
    }
  }

  clear(): void {
    this.profile = null;
  }
}
