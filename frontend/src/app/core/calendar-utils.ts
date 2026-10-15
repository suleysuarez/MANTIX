import { CalendarEvent } from './maintenance-overview.service';

/** Fechas del calendario en hora local. Funciones puras, sin Angular. */

export type CalendarMode = 'month' | 'week';

export const WEEKDAYS = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'] as const;
const WEEKDAYS_SUN_FIRST = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];
const MONTHS = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre',
  'noviembre', 'diciembre',
];

export const startOfDay = (date: Date): Date => new Date(date.getFullYear(), date.getMonth(), date.getDate());

export const addDays = (date: Date, days: number): Date =>
  new Date(date.getFullYear(), date.getMonth(), date.getDate() + days);

export const sameDay = (a: Date, b: Date): boolean =>
  a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();

/** Clave estable `YYYY-MM-DD` del día local. */
export function dayKey(date: Date): string {
  const month = String(date.getMonth() + 1).padStart(2, '0');
  return `${date.getFullYear()}-${month}-${String(date.getDate()).padStart(2, '0')}`;
}

/** Lunes de la semana de `date` (semana Lun–Dom). */
export function startOfWeek(date: Date): Date {
  const offset = (date.getDay() + 6) % 7;
  return addDays(startOfDay(date), -offset);
}

export interface CalendarDay {
  date: Date;
  key: string;
  inMonth: boolean;
  today: boolean;
}

/** Cuadrícula del mes en semanas completas (4 a 6 filas) que empiezan en lunes. */
export function monthGrid(anchor: Date, today: Date = new Date()): CalendarDay[] {
  const first = new Date(anchor.getFullYear(), anchor.getMonth(), 1);
  const last = new Date(anchor.getFullYear(), anchor.getMonth() + 1, 0);
  const start = startOfWeek(first);
  const end = addDays(startOfWeek(last), 7);
  const days: CalendarDay[] = [];
  for (let day = start; day < end; day = addDays(day, 1)) {
    days.push({ date: day, key: dayKey(day), inMonth: day.getMonth() === anchor.getMonth(), today: sameDay(day, today) });
  }
  return days;
}

export function weekDays(anchor: Date, today: Date = new Date()): CalendarDay[] {
  const start = startOfWeek(anchor);
  return Array.from({ length: 7 }, (_, i) => {
    const date = addDays(start, i);
    return { date, key: dayKey(date), inMonth: true, today: sameDay(date, today) };
  });
}

/** Rango `[start, end)` que cubre la vista (para pedirlo al servidor). */
export function visibleRange(anchor: Date, mode: CalendarMode): { start: Date; end: Date } {
  const days = mode === 'month' ? monthGrid(anchor) : weekDays(anchor);
  return { start: days[0].date, end: addDays(days[days.length - 1].date, 1) };
}

/** Mueve el ancla un mes o una semana. */
export function shift(anchor: Date, mode: CalendarMode, direction: -1 | 1): Date {
  return mode === 'month'
    ? new Date(anchor.getFullYear(), anchor.getMonth() + direction, 1)
    : addDays(anchor, 7 * direction);
}

export function rangeTitle(anchor: Date, mode: CalendarMode): string {
  if (mode === 'month') {
    return `${MONTHS[anchor.getMonth()]} ${anchor.getFullYear()}`;
  }
  const days = weekDays(anchor);
  const [first, last] = [days[0].date, days[6].date];
  const month = (d: Date) => MONTHS[d.getMonth()].slice(0, 3);
  return first.getMonth() === last.getMonth()
    ? `${first.getDate()}–${last.getDate()} ${month(last)} ${last.getFullYear()}`
    : `${first.getDate()} ${month(first)} – ${last.getDate()} ${month(last)} ${last.getFullYear()}`;
}

/** «Lun 13»: día de la semana y fecha. */
export const dayLabel = (date: Date): string => `${WEEKDAYS_SUN_FIRST[date.getDay()]} ${date.getDate()}`;

/** Agrupa los eventos por día local. */
export function groupByDay(events: CalendarEvent[]): Map<string, CalendarEvent[]> {
  const groups = new Map<string, CalendarEvent[]>();
  for (const event of events) {
    const key = dayKey(new Date(event.at));
    groups.set(key, [...(groups.get(key) ?? []), event]);
  }
  return groups;
}

/** Valor para `<input type="datetime-local">` (hora local, sin segundos). */
export function toLocalInput(date: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${dayKey(date)}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

/** ISO UTC de un valor de `datetime-local`; `null` si no existe ese instante (p. ej. 30 de febrero). */
export function fromLocalInput(value: string): string | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(value);
  if (!match) {
    return null;
  }
  const [year, month, day, hour, minute] = match.slice(1).map(Number);
  const date = new Date(year, month - 1, day, hour, minute);
  const exists =
    date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day &&
    date.getHours() === hour && date.getMinutes() === minute;
  return exists ? date.toISOString() : null;
}
