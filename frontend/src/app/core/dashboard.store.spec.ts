import { TestBed } from '@angular/core/testing';
import { of, throwError } from 'rxjs';

import {
  AlertsResponse,
  DashboardKpisService,
  KpisResponse,
  TechniciansPerformanceResponse,
  TrendsResponse,
} from './dashboard-kpis.service';
import { DashboardState, DashboardStore } from './dashboard.store';

const kpi = { value: 1, previous: null, change_pct: null, sample_size: 1 };
const kpis = {
  period: '30d', mttr_hours: kpi, first_assignment_hours: kpi, resolution_rate_pct: kpi,
  sla_compliance_pct: { ...kpi, met: 1, missed: 0, excluded_no_sla: 2 },
  backlog: { open: 0, age_0_2_days: 0, age_3_7_days: 0, age_over_7_days: 0 },
  availability: { value: 100, operational: 1, total: 1 },
} as unknown as KpisResponse;
const trends = { period: '30d', granularity: 'day', points: [] } as unknown as TrendsResponse;
const alerts = { tickets: [], down_equipment: [], schedules: [] } as unknown as AlertsResponse;

describe('DashboardStore', () => {
  let api: jasmine.SpyObj<DashboardKpisService>;
  let store: DashboardStore;
  let latest: DashboardState;

  beforeEach(() => {
    api = jasmine.createSpyObj('DashboardKpisService', ['kpis', 'trends', 'alerts', 'topFailingEquipment', 'technicians']);
    api.kpis.and.returnValue(of(kpis));
    api.trends.and.returnValue(of(trends));
    api.alerts.and.returnValue(of(alerts));
    api.topFailingEquipment.and.returnValue(of({ window_days: 30, equipment: [] }));
    api.technicians.and.returnValue(of({ period: '30d', technicians: [] } as unknown as TechniciansPerformanceResponse));
    TestBed.configureTestingModule({
      providers: [
        DashboardStore,
        { provide: DashboardKpisService, useValue: api },
      ],
    });
    store = TestBed.inject(DashboardStore);
    store.state$.subscribe((state) => (latest = state));
  });

  it('loads every source for the default period', () => {
    store.load();
    expect(latest.loading).toBeFalse();
    expect(latest.period).toBe('30d');
    expect(latest.kpis).toBe(kpis);
    expect(latest.topEquipment).toEqual([]);
    expect(api.kpis).toHaveBeenCalledWith('30d');
  });

  it('asks every source for the chosen global period and keeps it for reloads', () => {
    store.load('12m');
    expect(api.trends).toHaveBeenCalledWith('12m');
    expect(api.topFailingEquipment).toHaveBeenCalledWith('12m');
    expect(api.technicians).toHaveBeenCalledWith('12m');
    store.load();
    expect(api.kpis).toHaveBeenCalledTimes(2);
    expect(api.kpis.calls.mostRecent().args).toEqual(['12m']);
  });

  it('survives a failing source and leaves it null', () => {
    api.alerts.and.returnValue(throwError(() => new Error('403')));
    store.load();
    expect(latest.alerts).toBeNull();
    expect(latest.kpis).toBe(kpis);
    expect(latest.loading).toBeFalse();
  });
});
