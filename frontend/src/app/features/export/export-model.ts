import { ExportApiFilters } from '../../core/export.service';
import { dayBoundaryIso } from '../reports/report-filters';

/** Lógica pura del panel de exportación: atajos de fechas, filtros del servidor y textos. */

export interface ExportFilterValues {
  statuses: string[];
  priorities: string[];
  categories: string[];
  technicianIds: number[];
  /** `yyyy-MM-dd` (día local); vacío = sin límite. */
  dateFrom: string;
  dateTo: string;
}

export const EMPTY_EXPORT_FILTERS: ExportFilterValues = {
  statuses: [],
  priorities: [],
  categories: [],
  technicianIds: [],
  dateFrom: '',
  dateTo: '',
};

/** Filtros en el formato del servidor; lo vacío no se envía y una fecha inválida tampoco. */
export function toExportFilters(values: ExportFilterValues): ExportApiFilters {
  const filters: ExportApiFilters = {};
  if (values.statuses.length) {
    filters.statuses = values.statuses;
  }
  if (values.priorities.length) {
    filters.priorities = values.priorities;
  }
  if (values.categories.length) {
    filters.categories = values.categories;
  }
  if (values.technicianIds.length) {
    filters.technician_ids = values.technicianIds;
  }
  const from = dayBoundaryIso(values.dateFrom, false);
  const to = dayBoundaryIso(values.dateTo, true);
  if (from) {
    filters.date_from = from;
  }
  if (to) {
    filters.date_to = to;
  }
  return filters;
}

export const FORMAT_CARDS = [
  { id: 'pdf', title: 'PDF', icon: 'picture_as_pdf', text: 'Documento para imprimir o compartir: tabla, resumen ejecutivo y gráficos.' },
  { id: 'xlsx', title: 'Excel', icon: 'table_view', text: 'Hoja de cálculo para analizar: filtros, totales con fórmulas y gráficos.' },
] as const;

const grouped = (value: number): string => value.toLocaleString('es-CO');

/** Texto del contador en vivo. */
export function countMessage(total: number, maxRows: number, warnRows: number): { text: string; tone: 'ok' | 'warn' | 'error' } {
  if (total === 0) {
    return { text: 'Ningún registro coincide con estos filtros. Amplía el rango de fechas o quita algún filtro.', tone: 'error' };
  }
  if (total > maxRows) {
    return { text: `Son ${grouped(total)} registros y el máximo es ${grouped(maxRows)}. Acota los filtros para exportar.`, tone: 'error' };
  }
  const noun = total === 1 ? 'registro' : 'registros';
  const verb = total === 1 ? 'Se exportará' : 'Se exportarán';
  if (total > warnRows) {
    return { text: `${verb} ${grouped(total)} ${noun}. Es un archivo grande: puede tardar en generarse.`, tone: 'warn' };
  }
  return { text: `${verb} ${grouped(total)} ${noun}.`, tone: 'ok' };
}
