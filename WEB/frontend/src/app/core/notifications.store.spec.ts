import { TestBed } from '@angular/core/testing';
import { of, throwError } from 'rxjs';

import { AppNotification, NotificationsService } from './notifications.service';
import { NotificationsState, NotificationsStore } from './notifications.store';

const note = (id: number, is_read = false): AppNotification => ({
  id, title: `t${id}`, message: 'm', notification_type: 'role_assigned',
  is_read, read_at: null, link_url: null, created_at: '2026-01-01T00:00:00Z',
});

describe('NotificationsStore', () => {
  let api: jasmine.SpyObj<NotificationsService>;
  let store: NotificationsStore;
  let latest: NotificationsState;

  beforeEach(() => {
    api = jasmine.createSpyObj('NotificationsService', ['list', 'markRead', 'markAllRead']);
    TestBed.configureTestingModule({
      providers: [NotificationsStore, { provide: NotificationsService, useValue: api }],
    });
    store = TestBed.inject(NotificationsStore);
    store.state$.subscribe((state) => (latest = state));
  });

  it('publishes items and unread count once loaded', () => {
    api.list.and.returnValue(of({ unread_count: 1, items: [note(1), note(2, true)] }));
    store.load();
    expect(latest.items.length).toBe(2);
    expect(latest.unreadCount).toBe(1);
    expect(latest.loading).toBeFalse();
  });

  it('keeps the existing list when a refresh fails', () => {
    api.list.and.returnValue(of({ unread_count: 1, items: [note(1)] }));
    store.load();
    api.list.and.returnValue(throwError(() => new Error('down')));
    store.load();
    expect(latest.items.length).toBe(1);
    expect(latest.error).toBeTruthy();
  });

  it('marks one notification as read and lowers the counter', () => {
    api.list.and.returnValue(of({ unread_count: 1, items: [note(1)] }));
    store.load();
    api.markRead.and.returnValue(of(note(1, true)));
    store.markRead(1);
    expect(latest.items[0].is_read).toBeTrue();
    expect(latest.unreadCount).toBe(0);
  });

  it('does not call the API for an already read notification', () => {
    api.list.and.returnValue(of({ unread_count: 0, items: [note(1, true)] }));
    store.load();
    store.markRead(1);
    expect(api.markRead).not.toHaveBeenCalled();
  });

  it('marks everything as read', () => {
    api.list.and.returnValue(of({ unread_count: 2, items: [note(1), note(2)] }));
    store.load();
    api.markAllRead.and.returnValue(of(undefined));
    store.markAllRead();
    expect(latest.unreadCount).toBe(0);
    expect(latest.items.every((item) => item.is_read)).toBeTrue();
  });

  it('clear() drops the previous user state', () => {
    api.list.and.returnValue(of({ unread_count: 1, items: [note(1)] }));
    store.load();
    store.clear();
    expect(latest.items).toEqual([]);
    expect(latest.unreadCount).toBe(0);
  });
});
