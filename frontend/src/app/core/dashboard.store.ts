import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable, catchError, forkJoin, of } from 'rxjs';

import { Equipment, EquipmentService } from './equipment.service';
import { MaintenanceListItem, MaintenanceService } from './maintenance.service';
import { Technician, TechniciansService } from './technicians.service';

const OPERATIONAL_STATUSES = ['assigned', 'in_storage'];
const ACTIVE_STATUSES = ['assigned', 'in_progress', 'waiting'];
const PENDING_STATUSES = ['submitted', 'triaged'];
const DONE_STATUSES = ['resolved', 'closed'];
const DAY_LABELS = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];

export interface DayBar {
  label: string;
  count: number;
  isPeak: boolean;
}

export interface TypeCount {
  name: string;
  count: number;
}

export interface DashboardMetrics {
  equipmentTotal: number;
  operationalPct: number;
  byType: TypeCount[];
  activeTickets: number;
  urgentTickets: number;
  pendingTickets: number;
  monthTickets: number;
  monthDone: number;
  resolutionPct: number;
  week: DayBar[];
  weekTotal: number;
  techniciansTotal: number;
  techniciansAvailable: number;
  technicians: Technician[];
}

export interface DashboardState {
  loading: boolean;
  metrics: DashboardMetrics;
}

/** Pure: arma los indicadores del dashboard a partir de los listados del API. */
export function buildMetrics(
  equipment: Equipment[],
  tickets: MaintenanceListItem[],
  technicians: Technician[],
  now = new Date(),
): DashboardMetrics {
  const operational = equipment.filter((e) => OPERATIONAL_STATUSES.includes(e.status)).length;

  const typeTotals = new Map<string, number>();
  for (const item of equipment) {
    typeTotals.set(item.equipment_type.name, (typeTotals.get(item.equipment_type.name) ?? 0) + 1);
  }
  const byType = [...typeTotals.entries()]
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 3);

  const monthTickets = tickets.filter((t) => {
    const created = new Date(t.created_at);
    return created.getFullYear() === now.getFullYear() && created.getMonth() === now.getMonth();
  });
  const monthDone = monthTickets.filter((t) => DONE_STATUSES.includes(t.status)).length;

  const counts = new Map<string, number>();
  const days: { key: string; label: string }[] = [];
  for (let offset = 6; offset >= 0; offset--) {
    const day = new Date(now.getFullYear(), now.getMonth(), now.getDate() - offset);
    days.push({ key: day.toDateString(), label: DAY_LABELS[day.getDay()] });
  }
  for (const ticket of tickets) {
    const key = new Date(ticket.created_at).toDateString();
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  const rawWeek = days.map((day) => ({ label: day.label, count: counts.get(day.key) ?? 0 }));
  const peak = Math.max(...rawWeek.map((d) => d.count), 0);

  return {
    equipmentTotal: equipment.length,
    operationalPct: equipment.length ? Math.round((operational / equipment.length) * 100) : 0,
    byType,
    activeTickets: tickets.filter((t) => ACTIVE_STATUSES.includes(t.status)).length,
    urgentTickets: tickets.filter(
      (t) => !DONE_STATUSES.includes(t.status) && ['high', 'critical'].includes(t.priority),
    ).length,
    pendingTickets: tickets.filter((t) => PENDING_STATUSES.includes(t.status)).length,
    monthTickets: monthTickets.length,
    monthDone,
    resolutionPct: monthTickets.length ? Math.round((monthDone / monthTickets.length) * 100) : 0,
    week: rawWeek.map((d) => ({ ...d, isPeak: peak > 0 && d.count === peak })),
    weekTotal: rawWeek.reduce((sum, d) => sum + d.count, 0),
    techniciansTotal: technicians.length,
    techniciansAvailable: technicians.filter((t) => t.is_available).length,
    technicians: technicians.slice(0, 3),
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
  private readonly subject = new BehaviorSubject<DashboardState>({ loading: true, metrics: EMPTY });

  readonly state$: Observable<DashboardState> = this.subject.asObservable();

  load(): void {
    this.subject.next({ ...this.subject.value, loading: true });
    forkJoin({
      equipment: this.equipmentApi.listAll().pipe(catchError(() => of([] as Equipment[]))),
      tickets: this.maintenanceApi.list({ limit: 500 }).pipe(catchError(() => of([] as MaintenanceListItem[]))),
      technicians: this.techniciansApi.list().pipe(catchError(() => of([] as Technician[]))),
    }).subscribe(({ equipment, tickets, technicians }) =>
      this.subject.next({ loading: false, metrics: buildMetrics(equipment, tickets, technicians) }),
    );
  }
}
