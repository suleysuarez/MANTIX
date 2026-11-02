import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable, catchError, forkJoin, map, of } from 'rxjs';

import {
  AlertsResponse,
  DashboardKpisService,
  DashboardSummary,
  FailingEquipment,
  KpisResponse,
  Period,
  TechnicianPerformance,
  TrendsResponse,
} from './dashboard-kpis.service';

/**
 * Qué ve cada persona: `global` (toda la operación), `technician` (lo asignado a ella: su carga y su
 * rendimiento) o `requester` (el estado de sus propias solicitudes). Decide qué se pide, para no
 * llamar a endpoints que el rol no puede usar.
 */
export type DashboardMode = 'global' | 'technician' | 'requester';

export interface DashboardState {
  loading: boolean;
  period: Period;
  mode: DashboardMode;
  /** Solo para `requester`: sus solicitudes por estado. */
  mine: DashboardSummary | null;
  /** Cada fuente falla por separado: `null` significa «no disponible» y la tarjeta lo dice. */
  kpis: KpisResponse | null;
  trends: TrendsResponse | null;
  alerts: AlertsResponse | null;
  topEquipment: FailingEquipment[] | null;
  technicians: TechnicianPerformance[] | null;
}

const INITIAL: DashboardState = {
  loading: true,
  period: '30d',
  mode: 'global',
  mine: null,
  kpis: null,
  trends: null,
  alerts: null,
  topEquipment: null,
  technicians: null,
};

/**
 * Observer pattern store del dashboard. Los cálculos viven en el backend; el store solo
 * pide las fuentes del periodo global elegido y tolera que alguna falle (p. ej. 403).
 */
@Injectable({ providedIn: 'root' })
export class DashboardStore {
  private readonly api = inject(DashboardKpisService);
  private readonly subject = new BehaviorSubject<DashboardState>(INITIAL);

  readonly state$: Observable<DashboardState> = this.subject.asObservable();

  /** Carga las fuentes que el modo permite para `period`; sin argumentos repite el periodo y el modo actuales. */
  load(period: Period = this.subject.value.period, mode: DashboardMode = this.subject.value.mode): void {
    this.subject.next({ ...this.subject.value, period, mode, loading: true });
    const none = of(null);
    forkJoin({
      mine: mode === 'requester' ? this.api.summary(period).pipe(catchError(() => of(null))) : none,
      kpis: mode === 'requester' ? none : this.api.kpis(period).pipe(catchError(() => of(null))),
      trends: mode === 'requester' ? none : this.api.trends(period).pipe(catchError(() => of(null))),
      alerts: mode === 'requester' ? none : this.api.alerts().pipe(catchError(() => of(null))),
      // El ranking de equipos es de toda la operación: solo con `global`.
      topEquipment:
        mode === 'global'
          ? this.api.topFailingEquipment(period).pipe(
              map((response) => response.equipment),
              catchError(() => of(null)),
            )
          : none,
      technicians:
        mode === 'requester'
          ? none
          : this.api.technicians(period).pipe(
              map((response) => response.technicians),
              catchError(() => of(null)),
            ),
    }).subscribe((sources) => {
      // Una respuesta tardía de un periodo anterior no debe pisar el periodo elegido después.
      if (this.subject.value.period === period) {
        this.subject.next({ loading: false, period, mode, ...sources });
      }
    });
  }
}
