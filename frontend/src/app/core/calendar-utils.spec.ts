import { CalendarEvent } from './maintenance-overview.service';
import {
  dayKey, dayLabel, groupByDay, monthGrid, rangeTitle, shift, startOfWeek, visibleRange, weekDays,
} from './calendar-utils';

const event = (at: Date, schedule_id = 1): CalendarEvent => ({
  kind: 'planned', schedule_id, title: 't', equipment_id: 1, asset_tag: 'LT-1', technician: null,
  at: at.toISOString(), completed_at: null, on_time: null,
});

describe('calendar-utils', () => {
  it('starts weeks on Monday', () => {
    expect(dayKey(startOfWeek(new Date(2026, 9, 14)))).toBe('2026-10-12'); // miércoles -> lunes
    expect(dayKey(startOfWeek(new Date(2026, 9, 18)))).toBe('2026-10-12'); // domingo -> lunes anterior
  });

  it('builds a month grid of whole weeks that contains every day of the month', () => {
    const grid = monthGrid(new Date(2026, 9, 1), new Date(2026, 9, 14)); // octubre 2026
    expect(grid.length % 7).toBe(0);
    expect(grid.length).toBeLessThanOrEqual(42);
    expect(dayKey(grid[0].date)).toBe('2026-09-28'); // octubre empieza en jueves
    expect(grid.filter((d) => d.inMonth).length).toBe(31);
    expect(grid.filter((d) => d.today).map((d) => d.key)).toEqual(['2026-10-14']);
  });

  it('handles a month that fits in four weeks and one that needs six', () => {
    expect(monthGrid(new Date(2027, 1, 1)).length).toBe(28); // febrero 2027 empieza en lunes
    expect(monthGrid(new Date(2026, 7, 1)).length).toBe(42); // agosto 2026 empieza en sábado
  });

  it('never asks the server for more than its 62-day limit', () => {
    for (let month = 0; month < 12; month++) {
      const { start, end } = visibleRange(new Date(2026, month, 1), 'month');
      expect((end.getTime() - start.getTime()) / 86_400_000).toBeLessThanOrEqual(62);
    }
    const week = visibleRange(new Date(2026, 9, 14), 'week');
    expect(dayKey(week.start)).toBe('2026-10-12');
    expect(dayKey(week.end)).toBe('2026-10-19');
  });

  it('moves one month or one week at a time, across year boundaries', () => {
    expect(dayKey(shift(new Date(2026, 11, 1), 'month', 1))).toBe('2027-01-01');
    expect(dayKey(shift(new Date(2026, 0, 1), 'month', -1))).toBe('2025-12-01');
    expect(dayKey(shift(new Date(2026, 9, 14), 'week', 1))).toBe('2026-10-21');
  });

  it('titles the visible range in Spanish', () => {
    expect(rangeTitle(new Date(2026, 9, 1), 'month')).toBe('octubre 2026');
    expect(rangeTitle(new Date(2026, 9, 14), 'week')).toBe('12–18 oct 2026');
    expect(rangeTitle(new Date(2026, 9, 29), 'week')).toBe('26 oct – 1 nov 2026');
    expect(weekDays(new Date(2026, 9, 14)).length).toBe(7);
  });

  it('labels a day as weekday and date', () => {
    expect(dayLabel(new Date(2026, 9, 13))).toBe('Mar 13');
    expect(dayLabel(new Date(2026, 9, 18))).toBe('Dom 18');
  });

  it('groups events by local day', () => {
    const groups = groupByDay([event(new Date(2026, 9, 14, 9)), event(new Date(2026, 9, 14, 17), 2), event(new Date(2026, 9, 15, 8), 3)]);
    expect(groups.get('2026-10-14')?.length).toBe(2);
    expect(groups.get('2026-10-15')?.length).toBe(1);
  });
});
