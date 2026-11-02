import { MAX_RANGE_DAYS, parseDay } from '../features/reports/report-filters';

/** Atajos y validación de un rango de fechas (`yyyy-MM-dd`, día local): una sola regla para toda la app. */

export type RangeShortcut = 'all' | 'today' | '7d' | '30d' | 'month' | 'custom';

export const SHORTCUTS: { id: RangeShortcut; label: string }[] = [
  { id: 'all', label: 'Todo' },
  { id: 'today', label: 'Hoy' },
  { id: '7d', label: '7 días' },
  { id: '30d', label: '30 días' },
  { id: 'month', label: 'Este mes' },
  { id: 'custom', label: 'Personalizado' },
];

const DAY_MS = 86_400_000;
const pad = (value: number): string => String(value).padStart(2, '0');

export function dayString(date: Date): string {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/**
 * Rango de un atajo; `custom` conserva el actual (lo decide el usuario). Con `upcoming` los atajos
 * miran hacia adelante (para lo programado): «7 días» son hoy y los 6 siguientes y «Este mes» llega a fin de mes.
 */
export function shortcutRange(shortcut: RangeShortcut, today: Date, upcoming = false): { from: string; to: string } | null {
  const end = dayString(today);
  switch (shortcut) {
    case 'all':
      return { from: '', to: '' };
    case 'today':
      return { from: end, to: end };
    case '7d':
    case '30d': {
      const days = shortcut === '7d' ? 6 : 29;
      const other = dayString(new Date(today.getFullYear(), today.getMonth(), today.getDate() + (upcoming ? days : -days)));
      return upcoming ? { from: end, to: other } : { from: other, to: end };
    }
    case 'month':
      return {
        from: dayString(new Date(today.getFullYear(), today.getMonth(), 1)),
        to: upcoming ? dayString(new Date(today.getFullYear(), today.getMonth() + 1, 0)) : end,
      };
    default:
      return null;
  }
}

/** Atajo que corresponde a un rango ya elegido (para abrir el filtro con lo que traía la pantalla). */
export function shortcutOf(from: string, to: string, today: Date, upcoming = false): RangeShortcut {
  if (!from && !to) {
    return 'all';
  }
  for (const id of ['today', '7d', '30d', 'month'] as const) {
    const range = shortcutRange(id, today, upcoming);
    if (range && range.from === from && range.to === to) {
      return id;
    }
  }
  return 'custom';
}

/**
 * Error del rango, en español, o `''` si es válido: fechas reales, la inicial no es futura (salvo `allowFuture`),
 * la final no es anterior a la inicial y como máximo 366 días.
 */
export function dateRangeError(from: string, to: string, today: Date = new Date(), allowFuture = false): string {
  const start = from ? parseDay(from) : null;
  const end = to ? parseDay(to) : null;
  if ((from && !start) || (to && !end)) {
    return 'La fecha no existe en el calendario.';
  }
  if (!allowFuture && start && start.getTime() > today.getTime()) {
    return 'La fecha inicial no puede ser futura.';
  }
  if (start && end) {
    if (end < start) {
      return 'La fecha final no puede ser anterior a la inicial.';
    }
    if ((end.getTime() - start.getTime()) / DAY_MS + 1 > MAX_RANGE_DAYS) {
      return `El rango no puede superar ${MAX_RANGE_DAYS} días.`;
    }
  }
  return '';
}
