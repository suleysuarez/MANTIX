import {
  EQUIPMENT_STATUSES,
  activeGroup,
  categoryIcon,
  formatDate,
  groupCount,
  groupFilter,
  initials,
  pageWindow,
  statusBadgeClasses,
  statusInfo,
  ticketStatusLabel,
  workTypeLabel,
} from './equipment-status';

describe('equipment status vocabulary', () => {
  it('labels every status the API can return and falls back to the raw value', () => {
    for (const status of EQUIPMENT_STATUSES) {
      expect(statusInfo(status).label).not.toBe(status);
    }
    expect(statusInfo('mystery')).toEqual({ label: 'mystery', tone: 'neutral' });
  });

  it('colours healthy, in-repair and out-of-service statuses differently', () => {
    expect(statusInfo('assigned').tone).toBe('ok');
    expect(statusInfo('in_repair').tone).toBe('warn');
    expect(statusInfo('retired').tone).toBe('bad');
    expect(statusBadgeClasses('in_repair')).toContain('amber');
    expect(statusBadgeClasses('lost')).toContain('rose');
  });

  it('groups statuses for the summary cards', () => {
    const counts = { assigned: 10, in_storage: 4, in_repair: 3, lost: 1, retired: 2, disposed: 1 };
    expect(groupCount(counts, 'operational')).toBe(14);
    expect(groupCount(counts, 'maintenance')).toBe(3);
    expect(groupCount(counts, 'offline')).toBe(4);
    expect(groupCount({}, 'offline')).toBe(0);
  });

  it('builds the API status filter for a group and recognises it again', () => {
    expect(groupFilter('operational')).toBe('assigned,in_storage');
    expect(activeGroup('')).toBe('all');
    expect(activeGroup('in_repair')).toBe('maintenance');
    expect(activeGroup('in_storage,assigned')).toBe('operational'); // order does not matter
    expect(activeGroup('lost')).toBeNull();
  });

  it('picks an icon per category and a generic one for unknown categories', () => {
    expect(categoryIcon('laptop')).toBe('laptop_mac');
    expect(categoryIcon('SERVER')).toBe('dns');
    expect(categoryIcon('TOASTER')).toBe('devices_other');
  });

  it('formats dates without shifting calendar days across time zones', () => {
    expect(formatDate('2025-02-10')).toBe('10 feb 2025');
    expect(formatDate('2025-12-01')).toBe('01 dic 2025');
    expect(formatDate(null)).toBe('—');
    expect(formatDate('not a date')).toBe('—');
    expect(formatDate(new Date(2025, 2, 5, 13, 30).toISOString())).toBe('05 mar 2025');
  });

  it('builds initials from the first two words', () => {
    expect(initials('Carlos Rivera Soto')).toBe('CR');
    expect(initials('  ana ')).toBe('A');
    expect(initials('')).toBe('');
  });

  it('translates work types and ticket statuses', () => {
    expect(workTypeLabel('preventive')).toBe('Preventivo');
    expect(workTypeLabel('weird')).toBe('weird');
    expect(ticketStatusLabel('in_progress')).toBe('En curso');
  });
});

describe('pageWindow', () => {
  it('shows every page when there are few', () => {
    expect(pageWindow(1, 3)).toEqual([1, 2, 3]);
    expect(pageWindow(1, 1)).toEqual([1]);
    expect(pageWindow(1, 0)).toEqual([]);
  });

  it('collapses distant pages into ellipses around the current page', () => {
    expect(pageWindow(1, 20)).toEqual([1, 2, '…', 20]);
    expect(pageWindow(10, 20)).toEqual([1, '…', 9, 10, 11, '…', 20]);
    expect(pageWindow(20, 20)).toEqual([1, '…', 19, 20]);
    expect(pageWindow(3, 6)).toEqual([1, 2, 3, 4, '…', 6]);
  });
});
