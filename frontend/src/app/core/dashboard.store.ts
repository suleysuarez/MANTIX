import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable, catchError, forkJoin, map, of } from 'rxjs';

import {
  AlertsResponse,
  DashboardKpisService,
  FailingEquipment,
  KpisResponse,
  PERIOD_DAYS,
  Period,
  TrendsResponse,
} from './dashboard-kpis.service';
import { TechniciansService, TechnicianWorkload } from './technicians.service';

export interface DashboardState {
  loading: boolean;
  period: Period;
  /** Cada fuente falla por separado: `null` significa «no disponible» y la tarjeta lo dice. */
  kpis: KpisResponse | null;
  trends: TrendsResponse | null;
  alerts: AlertsResponse | null;
  topEquipment: FailingEquipment[] | null;
  workload: TechnicianWorkload[] | null;
}

const INITIAL: DashboardState = {
  loading: true,
  period: '30d',
  kpis: null,
  trends: null,
  alerts: null,
  topEquipment: null,
  workload: null,
};

/**
 * Observer pattern store del dashboard. Los cálculos viven en el backend; el store solo
 * pide las fuentes del periodo global elegido y tolera que alguna falle (p. ej. 403).
 */
@Injectable({ providedIn: 'root' })
export class DashboardStore {
  private readonly api = inject(DashboardKpisService);
  private readonly techniciansApi = inject(TechniciansService);
  private readonly subject = new BehaviorSubject<DashboardState>(INITIAL);

  readonly state$: Observable<DashboardState> = this.subject.asObservable();

  /** Carga todas las fuentes para `period`; sin argumento repite el periodo actual. */
  load(period: Period = this.subject.value.period): void {
    this.subject.next({ ...this.subject.value, period, loading: true });
    forkJoin({
      kpis: this.api.kpis(period).pipe(catchError(() => of(null))),
      trends: this.api.trends(period).pipe(catchError(() => of(null))),
      alerts: this.api.alerts().pipe(catchError(() => of(null))),
      topEquipment: this.api.topFailingEquipment(period).pipe(
        map((response) => response.equipment),
        catchError(() => of(null)),
      ),
      workload: this.techniciansApi.workload(PERIOD_DAYS[period]).pipe(
        map((response) => response.technicians),
        catchError(() => of(null)),
      ),
    }).subscribe((sources) => {
      // Una respuesta tardía de un periodo anterior no debe pisar el periodo elegido después.
      if (this.subject.value.period === period) {
        this.subject.next({ loading: false, period, ...sources });
      }
    });
  }
}
