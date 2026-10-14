import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable, catchError, forkJoin, map, of } from 'rxjs';

import { Equipment, EquipmentService } from './equipment.service';
import { MaintenanceListItem, MaintenanceService } from './maintenance.service';
import { MaintenanceSchedule, SchedulesService } from './schedules.service';
import { Technician, TechniciansService, TechnicianWorkload } from './technicians.service';

const OPERATIONAL_STATUSES = ['assigned', 'in_storage'];
const MAINTENANCE_STATUSES = ['in_repair'];
const OFFLINE_STATUSES = ['lost', 'retired', 'disposed'];
const ACTIVE_STATUSES = ['assigned', 'in_progress', 'waiting'];
const PENDING_STATUSES = ['submitted', 'triaged'];
const DONE_STATUSES = ['resolved', 'closed'];
const DAY_LABELS = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];
const MONTH_LABELS = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
const PRIORITY_RANK: Record<string, number> = { critical: 0, high: 1 };

export type SeriesPeriod = '7d' | '30d' | '12m';

export interface DayBar {
  label: string;
  count: number;
  isPeak: boolean;
}

export interface TypeCount {
  name: string;
  count: number;
}

/** Categorías mutuamente excluyentes: cada equipo cae en exactamente una. */
export interface HealthCounts {
  operational: number;
  maintenance: number;
  offline: number;
  other: number;
}

export interface AttentionItem {
  kind: 'ticket' | 'schedule' | 'equipment';
  title: string;
  equipment: string;
  detail: string;
  date: string | null;
  critical: boolean;
  link: string[];
}

export interface UpcomingItem {
  id: number;
  equipment: string;
  title: string;
  dueAt: string;
  technician: string | null;
  overdue: boolean;
}

export interface TechnicianRow {
  id: number;
  name: string;
  specialization: string | null;
  isAvailable: boolean;
  /** `null` cuando el API de carga de trabajo no respondió (no se inventa). */
  openTickets: number | null;
}

export interface DashboardMetrics {
  equipmentTotal: number;
  operationalPct: number;
  health: HealthCounts;
  byType: TypeCount[];
  tickets: MaintenanceListItem[];
  activeTickets: number;
  urgentTickets: number;
  pendingTickets: number;
  monthTickets: number;
  monthDone: number;
  /** Variación frente al mes anterior; `null` si el mes anterior no tiene solicitudes. */
  monthTrendPct: number | null;
  resolutionPct: number;
  overdueSchedules: number;
  attention: AttentionItem[];
  upcoming: UpcomingItem[];
  week: DayBar[];
  weekTotal: number;
  techniciansTotal: number;
  techniciansAvailable: number;
  technicians: Technician[];
  technicianRows: TechnicianRow[];
}

export interface DashboardState {
  loading: boolean;
  metrics: DashboardMetrics;
}

/** Pure: solicitudes creadas por día (7d, 30d) o por mes (12m); marca el máximo. */
export function buildSeries(tickets: { created_at: string }[], period: SeriesPeriod, now = new Date()): DayBar[] {
  const counts = new Map<string, number>();
  const buckets: { key: string; label: string }[] = [];
  if (period === '12m') {
    for (let offset = 11; offset >= 0; offset--) {
      const month = new Date(now.getFullYear(), now.getMonth() - offset, 1);
      buckets.push({ key: `${month.getFullYear()}-${month.getMonth()}`, label: MONTH_LABELS[month.getMonth()] });
    }
    for (const t of tickets) {
      const created = new Date(t.created_at);
      const key = `${created.getFullYear()}-${created.getMonth()}`;
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
  } else {
    const span = period === '7d' ? 7 : 30;
    for (let offset = span - 1; offset >= 0; offset--) {
      const day = new Date(now.getFullYear(), now.getMonth(), now.getDate() - offset);
      buckets.push({
        key: day.toDateString(),
        label: period === '7d' ? DAY_LABELS[day.getDay()] : String(day.getDate()),
      });
    }
    for (const t of tickets) {
      const key = new Date(t.created_at).toDateString();
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
  }
  const raw = buckets.map((b) => ({ label: b.label, count: counts.get(b.key) ?? 0 }));
  const peak = Math.max(...raw.map((d) => d.count), 0);
  return raw.map((d) => ({ ...d, isPeak: peak > 0 && d.count === peak }));
}

function isoDay(date: Date): string {
  const month = String(date.getMonth() + 1).padStart(2, '0');
  return `${date.getFullYear()}-${month}-${String(date.getDate()).padStart(2, '0')}`;
}

/** Pure: arma los indicadores del dashboard a partir de los listados del API. */
export function buildMetrics(
  equipment: Equipment[],
  tickets: MaintenanceListItem[],
  technicians: Technician[],
  now = new Date(),
  schedules: MaintenanceSchedule[] = [],
  workload: TechnicianWorkload[] | null = null,
): DashboardMetrics {
  const operational = equipment.filter((e) => OPERATIONAL_STATUSES.includes(e.status)).length;
  const maintenance = equipment.filter((e) => MAINTENANCE_STATUSES.includes(e.status)).length;
  const offline = equipment.filter((e) => OFFLINE_STATUSES.includes(e.status)).length;
  const health: HealthCounts = {
    operational,
    maintenance,
    offline,
    other: equipment.length - operational - maintenance - offline,
  };

  const typeTotals = new Map<string, number>();
  for (const item of equipment) {
    typeTotals.set(item.equipment_type.name, (typeTotals.get(item.equipment_type.name) ?? 0) + 1);
  }
  const byType = [...typeTotals.entries()]
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 3);

  const inMonth = (iso: string, ref: Date) => {
    const created = new Date(iso);
    return created.getFullYear() === ref.getFullYear() && created.getMonth() === ref.getMonth();
  };
  const monthTickets = tickets.filter((t) => inMonth(t.created_at, now));
  const monthDone = monthTickets.filter((t) => DONE_STATUSES.includes(t.status)).length;
  const prevMonth = new Date(now.getFullYear(), now.getMonth() - 1, 1);
  const prevCount = tickets.filter((t) => inMonth(t.created_at, prevMonth)).length;
  const monthTrendPct = prevCount ? Math.round(((monthTickets.length - prevCount) / prevCount) * 100) : null;

  const week = buildSeries(tickets, '7d', now);

  const equipmentLabel = new Map(equipment.map((e) => [e.id, `${e.asset_tag} · ${e.brand} ${e.model}`]));
  const today = isoDay(now);
  const overdue = schedules.filter((s) => s.is_active && s.next_due_at.slice(0, 10) < today);

  const attention: AttentionItem[] = [
    ...tickets
      .filter((t) => !DONE_STATUSES.includes(t.status) && t.status !== 'cancelled' && t.priority in PRIORITY_RANK)
      .sort((a, b) => PRIORITY_RANK[a.priority] - PRIORITY_RANK[b.priority] || a.created_at.localeCompare(b.created_at))
      .slice(0, 4)
      .map((t): AttentionItem => ({
        kind: 'ticket',
        title: t.title,
        equipment: equipmentLabel.get(t.equipment_id) ?? `Equipo #${t.equipment_id}`,
        detail: `${t.ticket_number} · prioridad ${t.priority === 'critical' ? 'crítica' : 'alta'}`,
        date: t.created_at,
        critical: t.priority === 'critical',
        link: ['/maintenance', String(t.id)],
      })),
    ...overdue.slice(0, 3).map((s): AttentionItem => ({
      kind: 'schedule',
      title: s.title,
      equipment: `${s.equipment.asset_tag} · ${s.equipment.brand} ${s.equipment.model}`,
      detail: 'Mantenimiento vencido',
      date: s.next_due_at,
      critical: false,
      link: ['/maintenance'],
    })),
    ...(offline > 0
      ? [{
          kind: 'equipment' as const,
          title: `${offline} equipo(s) fuera de servicio`,
          equipment: 'Extraviados, retirados o dados de baja',
          detail: 'Revisar inventario',
          date: null,
          critical: false,
          link: ['/equipos'],
        }]
      : []),
  ];

  const upcoming: UpcomingItem[] = schedules
    .filter((s) => s.is_active)
    .slice(0, 5)
    .map((s) => ({
      id: s.id,
      equipment: `${s.equipment.asset_tag} · ${s.equipment.brand} ${s.equipment.model}`,
      title: s.title,
      dueAt: s.next_due_at,
      technician: s.technician?.full_name ?? null,
      overdue: s.next_due_at.slice(0, 10) < today,
    }));

  const openByTech = new Map((workload ?? []).map((w) => [w.technician_id, w.open_tickets]));
  const technicianRows: TechnicianRow[] = technicians.slice(0, 4).map((t) => ({
    id: t.id,
    name: t.full_name,
    specialization: t.specialization,
    isAvailable: t.is_available,
    openTickets: workload ? (openByTech.get(t.id) ?? 0) : null,
  }));

  return {
    equipmentTotal: equipment.length,
    operationalPct: equipment.length ? Math.round((operational / equipment.length) * 100) : 0,
    health,
    byType,
    tickets,
    activeTickets: tickets.filter((t) => ACTIVE_STATUSES.includes(t.status)).length,
    urgentTickets: tickets.filter(
      (t) => !DONE_STATUSES.includes(t.status) && ['high', 'critical'].includes(t.priority),
    ).length,
    pendingTickets: tickets.filter((t) => PENDING_STATUSES.includes(t.status)).length,
    monthTickets: monthTickets.length,
    monthDone,
    monthTrendPct,
    resolutionPct: monthTickets.length ? Math.round((monthDone / monthTickets.length) * 100) : 0,
    overdueSchedules: overdue.length,
    attention,
    upcoming,
    week,
    weekTotal: week.reduce((sum, d) => sum + d.count, 0),
    techniciansTotal: technicians.length,
    techniciansAvailable: technicians.filter((t) => t.is_available).length,
    technicians: technicians.slice(0, 3),
    technicianRows,
  };
}

const EMPTY: DashboardMetrics = buildMetrics([], [], []);

/**
 * Observer pattern store del dashboard. Cada fuente falla por separado (p. ej. 403 si
 * el usuario no tiene ese permiso) y el panel muestra ceros en lugar de romperse.
 */
@Injectable({ providedIn: 'root' })
export class DashboardStore {
  private readonly equipmentApi = inject(EquipmentService);
  private readonly maintenanceApi = inject(MaintenanceService);
  private readonly techniciansApi = inject(TechniciansService);
  private readonly schedulesApi = inject(SchedulesService);
  private readonly subject = new BehaviorSubject<DashboardState>({ loading: true, metrics: EMPTY });

  readonly state$: Observable<DashboardState> = this.subject.asObservable();

  load(): void {
    this.subject.next({ ...this.subject.value, loading: true });
    forkJoin({
      equipment: this.equipmentApi.listAll().pipe(catchError(() => of([] as Equipment[]))),
      tickets: this.maintenanceApi.list({ limit: 500 }).pipe(catchError(() => of([] as MaintenanceListItem[]))),
      technicians: this.techniciansApi.list().pipe(catchError(() => of([] as Technician[]))),
      schedules: this.schedulesApi.listUpcoming().pipe(catchError(() => of([] as MaintenanceSchedule[]))),
      workload: this.techniciansApi.workload(30).pipe(
        map((response) => response.technicians),
        catchError(() => of(null)),
      ),
    }).subscribe(({ equipment, tickets, technicians, schedules, workload }) =>
      this.subject.next({
        loading: false,
        metrics: buildMetrics(equipment, tickets, technicians, new Date(), schedules, workload),
      }),
    );
  }
}
