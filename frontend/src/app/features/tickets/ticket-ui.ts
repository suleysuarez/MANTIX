import { MaintenanceListItem } from '../../core/maintenance.service';

/** Presentación de estados y prioridades del ticket (etiquetas en español y clases de chip). */
export interface ChipStyle {
  label: string;
  chip: string;
  dot: string;
}

export const STATUS_META: Record<string, ChipStyle> = {
  submitted: { label: 'Enviado', chip: 'bg-[#DBEAFE] text-[#1E40AF]', dot: 'bg-[#2563EB]' },
  triaged: { label: 'En triaje', chip: 'bg-[#E0E7FF] text-[#3730A3]', dot: 'bg-[#4F46E5]' },
  assigned: { label: 'Asignado', chip: 'bg-[#CFFAFE] text-[#155E75]', dot: 'bg-[#0891B2]' },
  in_progress: { label: 'En proceso', chip: 'bg-[#FEF3C7] text-[#92400E]', dot: 'bg-[#D4A017]' },
  waiting: { label: 'En espera', chip: 'bg-[#F3E8FF] text-[#6B21A8]', dot: 'bg-[#9333EA]' },
  resolved: { label: 'Resuelto', chip: 'bg-[#D1FAE5] text-[#065F46]', dot: 'bg-[#10B981]' },
  closed: { label: 'Cerrado', chip: 'bg-[#E2E8F0] text-[#334155]', dot: 'bg-[#64748B]' },
  cancelled: { label: 'Cancelado', chip: 'bg-[#F1F5F9] text-[#64748B] line-through', dot: 'bg-[#94A3B8]' },
};

export const PRIORITY_META: Record<string, ChipStyle> = {
  critical: { label: 'Crítica', chip: 'bg-[#FEE2E2] text-[#991B1B] ring-1 ring-[#EF4444]/20', dot: 'bg-[#DC2626]' },
  high: { label: 'Alta', chip: 'bg-[#FFEDD5] text-[#9A3412]', dot: 'bg-[#EA580C]' },
  medium: { label: 'Media', chip: 'bg-[#DBEAFE] text-[#1E40AF]', dot: 'bg-[#2563EB]' },
  low: { label: 'Baja', chip: 'bg-[#E2E8F0] text-[#475569]', dot: 'bg-[#94A3B8]' },
};

const FALLBACK: ChipStyle = { label: '', chip: 'bg-[#E2E8F0] text-[#334155]', dot: 'bg-[#94A3B8]' };

export const statusMeta = (status: string): ChipStyle =>
  STATUS_META[status] ?? { ...FALLBACK, label: status };

export const priorityMeta = (priority: string): ChipStyle =>
  PRIORITY_META[priority] ?? { ...FALLBACK, label: priority };

/** Columnas del kanban: un estado real por columna (los cancelados solo aparecen en la tabla). */
export const KANBAN_STATUSES = [
  'submitted', 'triaged', 'assigned', 'in_progress', 'waiting', 'resolved', 'closed',
] as const;

/** Estados en los que el ticket sigue pendiente de trabajo. */
const FINAL_STATUSES = ['resolved', 'closed', 'cancelled'];
/** Aún sin técnico: la regla del dominio exige uno para pasar a `assigned`. */
const UNASSIGNED_STATUSES = ['submitted', 'triaged'];

export const isActive = (status: string): boolean => !FINAL_STATUSES.includes(status);
export const isUnassigned = (status: string): boolean => UNASSIGNED_STATUSES.includes(status);

export const TRANSITION_LABELS: Record<string, string> = {
  triaged: 'Pasar a triaje',
  assigned: 'Marcar asignado',
  in_progress: 'Pasar a En proceso',
  waiting: 'Poner en espera',
  resolved: 'Marcar resuelto',
  closed: 'Cerrar ticket',
  cancelled: 'Cancelar',
};

export const TRANSITION_STYLES: Record<string, string> = {
  resolved: 'bg-[#059669] text-white hover:bg-[#047857]',
  closed: 'bg-[#0b1f3a] text-white hover:bg-[#3E5C76]',
  cancelled: 'bg-[#FEE2E2] text-[#991B1B] hover:bg-[#FECACA]',
};
export const DEFAULT_TRANSITION_STYLE = 'bg-[#E9EEF5] text-[#1E293B] hover:bg-[#DDE5EF]';

export const WORK_TYPE_LABELS: Record<string, string> = {
  corrective: 'Correctivo',
  preventive: 'Preventivo',
  inspection: 'Inspección',
  installation: 'Instalación',
  recovery: 'Recuperación',
  other: 'Otro',
};

export function initials(name: string): string {
  return name
    .split(' ')
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0].toUpperCase())
    .join('');
}

export function countByStatus(items: readonly MaintenanceListItem[]): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const item of items) {
    counts[item.status] = (counts[item.status] ?? 0) + 1;
  }
  return counts;
}

/** Tickets críticos o altos que siguen abiertos, los más urgentes primero. */
export function needingAttention(items: readonly MaintenanceListItem[]): MaintenanceListItem[] {
  const rank: Record<string, number> = { critical: 2, high: 1 };
  return items
    .filter((item) => item.priority in rank && isActive(item.status))
    .sort((a, b) => rank[b.priority] - rank[a.priority]);
}

function csvCell(value: string | number): string {
  const text = String(value);
  return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

export function ticketsToCsv(
  items: readonly MaintenanceListItem[],
  equipmentLabel: (equipmentId: number) => string,
): string {
  const header = ['Ticket', 'Título', 'Equipo', 'Prioridad', 'Estado', 'Creado'];
  const rows = items.map((item) => [
    item.ticket_number,
    item.title,
    equipmentLabel(item.equipment_id),
    priorityMeta(item.priority).label,
    statusMeta(item.status).label,
    item.created_at,
  ]);
  return [header, ...rows].map((row) => row.map(csvCell).join(',')).join('\r\n');
}
