import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { of } from 'rxjs';

import { MaintenanceService } from './maintenance.service';
import { TicketTransitionService } from './ticket-transitions.service';
import { WorkflowService, WorkflowState } from './workflow.service';

describe('WorkflowService', () => {
  const states: WorkflowState[] = [
    { status: 'submitted', order: 1, allowed_targets: ['assigned', 'cancelled', 'triaged'], requires: [], terminal: false },
    { status: 'closed', order: 7, allowed_targets: [], requires: [], terminal: true },
  ];

  it('reads the states from the server once and shares the answer', () => {
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting()] });
    const service = TestBed.inject(WorkflowService);
    const http = TestBed.inject(HttpTestingController);
    const received: WorkflowState[][] = [];
    service.states().subscribe((value) => received.push(value));
    service.states().subscribe((value) => received.push(value));
    const calls = http.match((request) => request.url.endsWith('/maintenance/requests/workflow'));
    expect(calls.length).toBe(1);
    calls[0].flush(states);
    expect(received).toEqual([states, states]);
    service.states().subscribe((value) => received.push(value));
    http.expectNone((request) => request.url.endsWith('/maintenance/requests/workflow'));
    expect(received.length).toBe(3);
  });

  it('asks again after reset (for example after a network error)', () => {
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting()] });
    const service = TestBed.inject(WorkflowService);
    const http = TestBed.inject(HttpTestingController);
    service.states().subscribe();
    http.expectOne((r) => r.url.endsWith('/workflow')).flush(states);
    service.reset();
    service.states().subscribe();
    http.expectOne((r) => r.url.endsWith('/workflow')).flush(states);
  });
});

describe('TicketTransitionService', () => {
  let api: jasmine.SpyObj<MaintenanceService>;
  let service: TicketTransitionService;

  beforeEach(() => {
    api = jasmine.createSpyObj('MaintenanceService', ['classify', 'assign', 'reject', 'transition']);
    for (const method of ['classify', 'assign', 'reject', 'transition'] as const) {
      (api[method] as jasmine.Spy).and.returnValue(of({}));
    }
    TestBed.configureTestingModule({ providers: [{ provide: MaintenanceService, useValue: api }] });
    service = TestBed.inject(TicketTransitionService);
  });

  it('classifies with the category and priority chosen', () => {
    service.move(7, 'submitted', 'triaged', { category: 'network', priority: 'high' }).subscribe();
    expect(api.classify).toHaveBeenCalledWith(7, { category: 'network', priority: 'high', notes: null });
  });

  it('assigns the chosen technician', () => {
    service.move(7, 'triaged', 'assigned', { technicianId: 4 }).subscribe();
    expect(api.assign).toHaveBeenCalledWith(7, 4, null);
  });

  it('rejects (with the reason) while the work has not started, and cancels with a note afterwards', () => {
    for (const from of ['submitted', 'triaged', 'assigned']) {
      service.move(7, from, 'cancelled', { reason: 'Duplicado' }).subscribe();
    }
    expect(api.reject).toHaveBeenCalledTimes(3);
    expect(api.reject).toHaveBeenCalledWith(7, 'Duplicado');
    service.move(7, 'in_progress', 'cancelled', { reason: 'Ya no hace falta' }).subscribe();
    expect(api.transition).toHaveBeenCalledWith(7, 'cancelled', 'Ya no hace falta', null);
  });

  it('resolves with the summary and changes any other state directly', () => {
    service.move(7, 'in_progress', 'resolved', { resolutionSummary: 'Listo' }).subscribe();
    expect(api.transition).toHaveBeenCalledWith(7, 'resolved', null, 'Listo');
    service.move(7, 'assigned', 'in_progress', {}).subscribe();
    expect(api.transition).toHaveBeenCalledWith(7, 'in_progress', null, null);
    service.move(7, 'resolved', 'closed', {}).subscribe();
    expect(api.transition).toHaveBeenCalledWith(7, 'closed', null, null);
  });
});
