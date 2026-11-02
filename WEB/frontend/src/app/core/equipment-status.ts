/**
 * Vocabulario visual del catálogo de equipos: etiquetas en español, tono de color
 * por estado, agrupación para las tarjetas resumen e icono por categoría.
 * Todo son funciones puras para poder probarlas sin Angular.
 */

export const EQUIPMENT_STATUSES = [
  'in_storage',
  'assigned',
  'in_repair',
  'lost',
  'retired',
  'disposed',
] as const;

export type StatusTone = 'ok' | 'warn' | 'bad' | 'neutral';

export interface StatusInfo {
  label: string;
  tone: StatusTone;
}

const STATUS_INFO: Record<string, StatusInfo> = {
  in_storage: { label: 'En almacén', tone: 'ok' },
  assigned: { label: 'Asignado', tone: 'ok' },
  in_repair: { label: 'En mantenimiento', tone: 'warn' },
  lost: { label: 'Extraviado', tone: 'bad' },
  retired: { label: 'Retirado', tone: 'bad' },
  disposed: { label: 'Dado de baja', tone: 'bad' },
};

export function statusInfo(status: string): StatusInfo {
  return STATUS_INFO[status] ?? { label: status, tone: 'neutral' };
}

/** Clases literales (Tailwind solo genera las que ve escritas completas). */
export const TONE_CLASSES: Record<StatusTone, { badge: string; dot: string }> = {
  ok: { badge: 'bg-emerald-50 text-emerald-700 border-emerald-200', dot: 'bg-emerald-500' },
  warn: { badge: 'bg-amber-50 text-amber-700 border-amber-200', dot: 'bg-[#E4B363]' },
  bad: { badge: 'bg-rose-50 text-rose-700 border-rose-200', dot: 'bg-rose-500' },
  neutral: { badge: 'bg-slate-100 text-slate-600 border-slate-200', dot: 'bg-slate-400' },
};

export function statusBadgeClasses(status: string): string {
  return TONE_CLASSES[statusInfo(status).tone].badge;
}

export function statusDotClasses(status: string): string {
  return TONE_CLASSES[statusInfo(status).tone].dot;
}

/** Grupos de las tarjetas resumen; el filtro de la API acepta la lista separada por comas. */
export const STATUS_GROUPS = {
  operational: ['assigned', 'in_storage'],
  maintenance: ['in_repair'],
  offline: ['lost', 'retired', 'disposed'],
} as const;

export type StatusGroup = keyof typeof STATUS_GROUPS;

export function groupCount(byStatus: Readonly<Record<string, number>>, group: StatusGroup): number {
  return STATUS_GROUPS[group].reduce((sum, status) => sum + (byStatus[status] ?? 0), 0);
}

export function groupFilter(group: StatusGroup): string {
  return STATUS_GROUPS[group].join(',');
}

/** Qué tarjeta está activa para el filtro de estado actual (`null` si ninguna coincide). */
export function activeGroup(statusFilter: string): StatusGroup | 'all' | null {
  if (!statusFilter) {
    return 'all';
  }
  const wanted = [...statusFilter.split(',')].sort().join(',');
  for (const group of Object.keys(STATUS_GROUPS) as StatusGroup[]) {
    if ([...STATUS_GROUPS[group]].sort().join(',') === wanted) {
      return group;
    }
  }
  return null;
}

const CATEGORY_ICONS: Record<string, string> = {
  LAPTOP: 'laptop_mac',
  DESKTOP: 'desktop_windows',
  MONITOR: 'monitor',
  PRINTER: 'print',
  SERVER: 'dns',
  NETWORK_EQUIPMENT: 'router',
  MOBILE_DEVICE: 'smartphone',
};

export function categoryIcon(typeCode: string): string {
  return CATEGORY_ICONS[typeCode.toUpperCase()] ?? 'devices_other';
}

const MONTHS = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/** "10 feb 2025", independiente del idioma del navegador y de la zona horaria para fechas puras. */
export function formatDate(value: string | null | undefined): string {
  if (!value) {
    return '—';
  }
  const dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  const parts = dateOnly
    ? { year: +dateOnly[1], month: +dateOnly[2] - 1, day: +dateOnly[3] }
    : (() => {
        const date = new Date(value);
        return Number.isNaN(date.getTime())
          ? null
          : { year: date.getFullYear(), month: date.getMonth(), day: date.getDate() };
      })();
  if (!parts) {
    return '—';
  }
  return `${String(parts.day).padStart(2, '0')} ${MONTHS[parts.month]} ${parts.year}`;
}

export function initials(name: string): string {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0].toUpperCase())
    .join('');
}

const WORK_TYPE_LABELS: Record<string, string> = {
  corrective: 'Correctivo',
  preventive: 'Preventivo',
  inspection: 'Inspección',
  installation: 'Instalación',
  recovery: 'Recuperación',
  other: 'Otro',
};

export function workTypeLabel(workType: string): string {
  return WORK_TYPE_LABELS[workType] ?? workType;
}

const TICKET_STATUS_LABELS: Record<string, string> = {
  submitted: 'Recibido',
  triaged: 'Clasificado',
  assigned: 'Asignado',
  in_progress: 'En curso',
  waiting: 'En espera',
  resolved: 'Resuelto',
  closed: 'Cerrado',
  cancelled: 'Cancelado',
};

export function ticketStatusLabel(status: string): string {
  return TICKET_STATUS_LABELS[status] ?? status;
}

/** Ventana de páginas con puntos suspensivos: [1, '…', 4, 5, 6, '…', 20]. */
export function pageWindow(current: number, total: number, radius = 1): (number | '…')[] {
  if (total <= 1) {
    return total === 1 ? [1] : [];
  }
  const pages = new Set<number>([1, total]);
  for (let page = current - radius; page <= current + radius; page++) {
    if (page >= 1 && page <= total) {
      pages.add(page);
    }
  }
  const ordered = [...pages].sort((a, b) => a - b);
  const result: (number | '…')[] = [];
  ordered.forEach((page, index) => {
    if (index > 0 && page - ordered[index - 1] > 1) {
      result.push('…');
    }
    result.push(page);
  });
  return result;
}
