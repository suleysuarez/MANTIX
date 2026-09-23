import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { BehaviorSubject, Observable, tap } from 'rxjs';

export interface User {
  id: number;
  email: string;
  full_name: string;
  employee_code: string | null;
  is_active: boolean;
  roles: { code: string; name: string }[];
  permissions: { code: string; name: string }[];
}

export interface TokenResponse {
  access_token: string;
  refresh_token: string;
  token_type: string;
  expires_in: number;
  user: User;
}

@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly http = inject(HttpClient);
  private readonly apiUrl = 'http://localhost:8000';
  private readonly accessKey = 'maintenance_access_token';
  private readonly refreshKey = 'maintenance_refresh_token';
  private readonly userSubject = new BehaviorSubject<User | null>(null);
  readonly user$ = this.userSubject.asObservable();

  login(email: string, password: string): Observable<TokenResponse> {
    return this.http.post<TokenResponse>(`${this.apiUrl}/auth/login`, { email, password }).pipe(
      tap((response) => this.storeSession(response)),
    );
  }

  loadCurrentUser(): Observable<User> {
    return this.http.get<User>(`${this.apiUrl}/auth/me`).pipe(tap((user) => this.userSubject.next(user)));
  }

  refresh(): Observable<TokenResponse> {
    return this.http
      .post<TokenResponse>(`${this.apiUrl}/auth/refresh`, { refresh_token: this.refreshToken })
      .pipe(tap((response) => this.storeSession(response)));
  }

  logout(): Observable<{ message: string }> {
    const refreshToken = this.refreshToken;
    this.clearSession();
    return this.http.post<{ message: string }>(`${this.apiUrl}/auth/logout`, { refresh_token: refreshToken });
  }

  get accessToken(): string | null {
    return localStorage.getItem(this.accessKey);
  }

  get refreshToken(): string | null {
    return localStorage.getItem(this.refreshKey);
  }

  get isAuthenticated(): boolean {
    return Boolean(this.accessToken && this.refreshToken);
  }

  clearSession(): void {
    localStorage.removeItem(this.accessKey);
    localStorage.removeItem(this.refreshKey);
    this.userSubject.next(null);
  }

  private storeSession(response: TokenResponse): void {
    localStorage.setItem(this.accessKey, response.access_token);
    localStorage.setItem(this.refreshKey, response.refresh_token);
    this.userSubject.next(response.user);
  }
}
