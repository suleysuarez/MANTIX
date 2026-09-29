import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, tap } from 'rxjs';

import { LocalProfileService } from './local-profile.service';

export interface PendingUser {
  id: number;
  email: string;
  full_name: string;
}

export interface AdminRole {
  id: number;
  code: string;
  name: string;
}

export interface ManagedUser {
  id: number;
  email: string;
  full_name: string;
  role_ids: number[];
}

@Injectable({ providedIn: 'root' })
export class AdminUsersService {
  private readonly http = inject(HttpClient);
  private readonly profile = inject(LocalProfileService);
  private readonly apiUrl = 'http://localhost:8000';

  listPendingUsers(): Observable<PendingUser[]> {
    return this.http.get<PendingUser[]>(`${this.apiUrl}/admin/users/pending`);
  }

  listRoles(): Observable<AdminRole[]> {
    return this.http.get<AdminRole[]>(`${this.apiUrl}/admin/roles`);
  }

  assignRoles(userId: number, roleIds: number[]): Observable<ManagedUser> {
    return this.http
      .post<ManagedUser>(`${this.apiUrl}/admin/users/${userId}/roles`, {
        role_ids: roleIds,
      })
      .pipe(tap(() => this.profile.clear()));
  }
}
