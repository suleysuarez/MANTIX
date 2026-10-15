import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { apiBaseUrl } from './api.config';

export interface AppNotification {
  id: number;
  title: string;
  message: string;
  notification_type: string;
  is_read: boolean;
  read_at: string | null;
  link_url: string | null;
  created_at: string;
}

export interface NotificationList {
  unread_count: number;
  items: AppNotification[];
}

@Injectable({ providedIn: 'root' })
export class NotificationsService {
  private readonly http = inject(HttpClient);
  private readonly url = `${apiBaseUrl()}/notifications`;

  list(): Observable<NotificationList> {
    return this.http.get<NotificationList>(this.url);
  }

  markRead(id: number): Observable<AppNotification> {
    return this.http.post<AppNotification>(`${this.url}/${id}/read`, {});
  }

  markAllRead(): Observable<void> {
    return this.http.post<void>(`${this.url}/read-all`, {});
  }
}
